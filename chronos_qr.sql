/* ============================================================
   Chronos ITT — Módulo de Asistencia con Código QR
   Motor: SQL Server (T-SQL)

   Flujo que modela este esquema:
     1) El docente abre una Sesion para su Grupo -> se genera un
        token_qr unico (el QR proyectado codifica una URL con ese
        token + la IP local del servidor).
     2) El alumno escanea, inicia sesion como Alumno, y el backend
        llama a sp_RegistrarAsistenciaQR con el token leido del QR.
     3) Al terminar la clase, el docente "cierra" la sesion
        (sp_CerrarSesion) y a quien no escaneo se le marca ausente.
     4) Los reportes (3 retardos = 1 falta, 20% de faltas = riesgo
        de baja) se calculan con las vistas al final del archivo.
   ============================================================ */

-- ------------------------------------------------------------
-- CATALOGOS BASE
-- ------------------------------------------------------------
CREATE TABLE Periodos (
    id            INT IDENTITY(1,1) PRIMARY KEY,
    nombre        VARCHAR(100) NOT NULL,        -- ej. 'Agosto-Diciembre 2026'
    fecha_inicio  DATE NOT NULL,
    fecha_fin     DATE NOT NULL
);

CREATE TABLE Materias (
    id     INT IDENTITY(1,1) PRIMARY KEY,
    clave  VARCHAR(20)  NOT NULL UNIQUE,
    nombre VARCHAR(150) NOT NULL
);

CREATE TABLE Docentes (
    id               INT IDENTITY(1,1) PRIMARY KEY,
    numero_empleado  VARCHAR(20)  NOT NULL UNIQUE,
    nombre           VARCHAR(150) NOT NULL
);

CREATE TABLE Alumnos (
    id        INT IDENTITY(1,1) PRIMARY KEY,
    matricula VARCHAR(20)  NOT NULL UNIQUE,
    nombre    VARCHAR(150) NOT NULL,
    carrera   VARCHAR(100) NULL
);

-- Login del sistema. rol='administrador' es quien gestiona catalogos;
-- 'docente' genera QRs de su propio grupo; 'alumno' solo escanea/consulta.
CREATE TABLE Usuarios (
    id             INT IDENTITY(1,1) PRIMARY KEY,
    identificador  VARCHAR(20)  NOT NULL UNIQUE,   -- matricula, no. empleado, o usuario admin
    nombre         VARCHAR(150) NOT NULL,
    password_hash  VARCHAR(256) NOT NULL,
    rol            VARCHAR(20)  NOT NULL
                   CHECK (rol IN ('administrador','docente','alumno')),
    docente_id     INT NULL,
    alumno_id      INT NULL,
    CONSTRAINT FK_Usuarios_Docente FOREIGN KEY (docente_id) REFERENCES Docentes(id),
    CONSTRAINT FK_Usuarios_Alumno  FOREIGN KEY (alumno_id)  REFERENCES Alumnos(id)
);

CREATE TABLE Grupos (
    id          INT IDENTITY(1,1) PRIMARY KEY,
    nombre      VARCHAR(20) NOT NULL,        -- ej. '08B'
    materia_id  INT NOT NULL,
    docente_id  INT NOT NULL,
    periodo_id  INT NOT NULL,
    horario     VARCHAR(100) NULL,
    CONSTRAINT FK_Grupos_Materia FOREIGN KEY (materia_id) REFERENCES Materias(id),
    CONSTRAINT FK_Grupos_Docente FOREIGN KEY (docente_id) REFERENCES Docentes(id),
    CONSTRAINT FK_Grupos_Periodo FOREIGN KEY (periodo_id) REFERENCES Periodos(id)
);

-- Un alumno puede estar inscrito en varios grupos (una materia c/u)
CREATE TABLE Inscripciones (
    grupo_id  INT NOT NULL,
    alumno_id INT NOT NULL,
    PRIMARY KEY (grupo_id, alumno_id),
    CONSTRAINT FK_Inscripciones_Grupo  FOREIGN KEY (grupo_id)  REFERENCES Grupos(id),
    CONSTRAINT FK_Inscripciones_Alumno FOREIGN KEY (alumno_id) REFERENCES Alumnos(id)
);

-- ------------------------------------------------------------
-- NUCLEO DEL FLUJO QR
-- ------------------------------------------------------------

-- Una fila por cada QR que el docente genera para una clase.
CREATE TABLE Sesiones (
    id                          INT IDENTITY(1,1) PRIMARY KEY,
    grupo_id                    INT NOT NULL,
    fecha                       DATE NOT NULL,
    hora_inicio                 TIME NOT NULL,
    duracion_minutos            INT NOT NULL DEFAULT 60,
    minutos_tolerancia_retardo  INT NOT NULL DEFAULT 10,   -- regla configurable de "retardo"
    token_qr                    UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID(),  -- lo que codifica el QR
    ip_servidor                 VARCHAR(45) NOT NULL,       -- IP local de la laptop del docente
    fecha_generacion            DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
    estado                      VARCHAR(10) NOT NULL DEFAULT 'abierta'
                                CHECK (estado IN ('abierta','cerrada')),
    CONSTRAINT FK_Sesiones_Grupo FOREIGN KEY (grupo_id) REFERENCES Grupos(id),
    CONSTRAINT UQ_Sesiones_Token UNIQUE (token_qr),
    CONSTRAINT UQ_Sesiones_GrupoFecha UNIQUE (grupo_id, fecha)  -- 1 sesion de QR por grupo/dia
);

-- Un registro por alumno que escaneo (o al que se le marco falta/justificante).
CREATE TABLE Asistencias (
    id                   INT IDENTITY(1,1) PRIMARY KEY,
    sesion_id            INT NOT NULL,
    alumno_id            INT NOT NULL,
    fecha_hora_registro  DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
    ip_alumno            VARCHAR(45) NULL,      -- IP desde la que escaneo (validar misma red)
    estado               VARCHAR(12) NOT NULL
                         CHECK (estado IN ('presente','retardo','ausente','justificado')),
    CONSTRAINT FK_Asistencias_Sesion FOREIGN KEY (sesion_id) REFERENCES Sesiones(id),
    CONSTRAINT FK_Asistencias_Alumno FOREIGN KEY (alumno_id) REFERENCES Alumnos(id),
    CONSTRAINT UQ_Asistencias_SesionAlumno UNIQUE (sesion_id, alumno_id)
);

-- ------------------------------------------------------------
-- INDICES para las consultas mas frecuentes
-- ------------------------------------------------------------
CREATE INDEX IX_Asistencias_Alumno   ON Asistencias(alumno_id);
CREATE INDEX IX_Sesiones_GrupoFecha  ON Sesiones(grupo_id, fecha);
CREATE INDEX IX_Grupos_Docente       ON Grupos(docente_id);

GO

-- ------------------------------------------------------------
-- sp_RegistrarAsistenciaQR
-- Se llama cuando el alumno escanea el QR y ya inicio sesion.
-- Calcula solo si es 'presente' o 'retardo' segun la tolerancia
-- de la sesion; si ya existia un registro, no lo duplica.
-- ------------------------------------------------------------
CREATE PROCEDURE sp_RegistrarAsistenciaQR
    @token_qr   UNIQUEIDENTIFIER,
    @alumno_id  INT,
    @ip_alumno  VARCHAR(45) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @sesion_id INT, @fecha DATE, @hora_inicio TIME,
            @tolerancia INT, @estado_sesion VARCHAR(10);

    SELECT @sesion_id = id, @fecha = fecha, @hora_inicio = hora_inicio,
           @tolerancia = minutos_tolerancia_retardo, @estado_sesion = estado
    FROM Sesiones
    WHERE token_qr = @token_qr;

    IF @sesion_id IS NULL
    BEGIN
        RAISERROR('Codigo QR invalido o expirado.', 16, 1);
        RETURN;
    END

    IF @estado_sesion = 'cerrada'
    BEGIN
        RAISERROR('Esta sesion ya fue cerrada, no se puede registrar asistencia.', 16, 1);
        RETURN;
    END

    IF NOT EXISTS (SELECT 1 FROM Inscripciones WHERE grupo_id = (SELECT grupo_id FROM Sesiones WHERE id=@sesion_id) AND alumno_id = @alumno_id)
    BEGIN
        RAISERROR('El alumno no esta inscrito en el grupo de esta sesion.', 16, 1);
        RETURN;
    END

    -- Combina fecha + hora_inicio en un solo DATETIME2 (patron estandar de T-SQL,
    -- mas seguro que concatenar strings porque no depende del formato regional).
    DECLARE @inicio_datetime DATETIME2 = DATEADD(DAY, DATEDIFF(DAY, 0, @fecha), CAST(@hora_inicio AS DATETIME2));
    DECLARE @minutos_transcurridos INT = DATEDIFF(MINUTE, @inicio_datetime, SYSDATETIME());

    DECLARE @estado VARCHAR(12) = CASE
        WHEN @minutos_transcurridos <= @tolerancia THEN 'presente'
        ELSE 'retardo'
    END;

    IF NOT EXISTS (SELECT 1 FROM Asistencias WHERE sesion_id = @sesion_id AND alumno_id = @alumno_id)
    BEGIN
        INSERT INTO Asistencias (sesion_id, alumno_id, ip_alumno, estado)
        VALUES (@sesion_id, @alumno_id, @ip_alumno, @estado);
    END

    SELECT @estado AS estado_registrado, @minutos_transcurridos AS minutos_transcurridos;
END
GO

-- ------------------------------------------------------------
-- sp_CerrarSesion
-- El docente la llama al terminar la clase: cierra el QR (deja
-- de aceptar escaneos) y marca 'ausente' a quien no paso lista.
-- ------------------------------------------------------------
CREATE PROCEDURE sp_CerrarSesion
    @sesion_id INT
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE Sesiones SET estado = 'cerrada' WHERE id = @sesion_id;

    DECLARE @grupo_id INT = (SELECT grupo_id FROM Sesiones WHERE id = @sesion_id);

    INSERT INTO Asistencias (sesion_id, alumno_id, estado)
    SELECT @sesion_id, i.alumno_id, 'ausente'
    FROM Inscripciones i
    WHERE i.grupo_id = @grupo_id
      AND NOT EXISTS (
          SELECT 1 FROM Asistencias a
          WHERE a.sesion_id = @sesion_id AND a.alumno_id = i.alumno_id
      );
END
GO

-- ------------------------------------------------------------
-- sp_JustificarFalta
-- El docente/admin sube evidencia (ya guardada aparte) y cambia
-- el estado de una falta a 'justificado'.
-- ------------------------------------------------------------
CREATE PROCEDURE sp_JustificarFalta
    @sesion_id INT,
    @alumno_id INT
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE Asistencias
    SET estado = 'justificado'
    WHERE sesion_id = @sesion_id AND alumno_id = @alumno_id;
END
GO

-- ------------------------------------------------------------
-- VISTAS DE REPORTE
-- ------------------------------------------------------------

-- Conteo crudo de asistencia por alumno y grupo
CREATE VIEW vw_ResumenAsistenciaAlumnoGrupo AS
SELECT
    al.id   AS alumno_id, al.matricula, al.nombre,
    g.id    AS grupo_id,  g.nombre AS grupo,
    COUNT(a.id)                                          AS total_sesiones,
    SUM(CASE WHEN a.estado='presente'    THEN 1 ELSE 0 END) AS presentes,
    SUM(CASE WHEN a.estado='retardo'     THEN 1 ELSE 0 END) AS retardos,
    SUM(CASE WHEN a.estado='ausente'     THEN 1 ELSE 0 END) AS ausentes,
    SUM(CASE WHEN a.estado='justificado' THEN 1 ELSE 0 END) AS justificados
FROM Asistencias a
JOIN Sesiones s  ON s.id  = a.sesion_id
JOIN Grupos   g  ON g.id  = s.grupo_id
JOIN Alumnos  al ON al.id = a.alumno_id
GROUP BY al.id, al.matricula, al.nombre, g.id, g.nombre;
GO

-- Igual que la anterior, pero ya con las reglas de negocio aplicadas:
-- 3 retardos = 1 falta; 20% de faltas equivalentes = riesgo de baja.
CREATE VIEW vw_RiesgoBajaAlumnoGrupo AS
SELECT *,
    (ausentes + (retardos / 3)) AS faltas_equivalentes,
    CAST(ROUND(
        100.0 - (CAST(ausentes + (retardos / 3) AS FLOAT) / NULLIF(total_sesiones, 0)) * 100
    , 1) AS FLOAT) AS porcentaje_asistencia,
    CASE
        WHEN CAST(ausentes + (retardos / 3) AS FLOAT) / NULLIF(total_sesiones, 0) >= 0.20 THEN 1
        ELSE 0
    END AS en_riesgo
FROM vw_ResumenAsistenciaAlumnoGrupo;
GO

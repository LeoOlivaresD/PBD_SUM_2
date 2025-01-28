-- DECLARACIÓN DE VARIABLES BIND
SET SERVEROUTPUT ON;

-- Variable BIND para definir el límite máximo de asignaciones
VARIABLE LIMITE_ASIGNACIONES NUMBER;

-- Asigno el valor $250,000 al límite de asignaciones
EXEC :LIMITE_ASIGNACIONES := 250000;

-- Variable BIND para especificar la fecha del proceso
VARIABLE FECHA_PROCESO VARCHAR2(7);

-- Asigno la fecha del proceso en formato MM/YYYY
EXEC :FECHA_PROCESO := '06/2021';

DECLARE
    -- Declaro un cursor para obtener todas las profesiones ordenadas alfabéticamente
    CURSOR C_RESUMEN_MES_PROF IS 
        SELECT NOMBRE_PROFESION 
        FROM PROFESION
        ORDER BY NOMBRE_PROFESION;

    -- Declaro un cursor para obtener los datos de profesionales en una profesión específica
    CURSOR C_DETALLE_ASIG_MES (P_NOMBRE_PROFESION VARCHAR2) IS
        SELECT PL.NUMRUN_PROF AS NUMRUN_PROF, 
               PL.NOMBRE || ' ' || PL.APPATERNO AS NOMBRE_PROF, 
               PN.NOMBRE_PROFESION AS PROFESION,
               PL.COD_COMUNA AS COD_COMUNA,
               PL.COD_TPCONTRATO AS COD_TPCONTRATO,
               PL.COD_PROFESION AS COD_PROFESION,
               PL.SUELDO AS SUELDO
        FROM PROFESIONAL PL
        INNER JOIN PROFESION PN ON PN.COD_PROFESION = PL.COD_PROFESION
        WHERE PN.NOMBRE_PROFESION = P_NOMBRE_PROFESION
          AND EXISTS (
              SELECT 1
              FROM ASESORIA A
              WHERE A.NUMRUN_PROF = PL.NUMRUN_PROF
                AND TO_CHAR(A.INICIO_ASESORIA, 'MM/YYYY') = :FECHA_PROCESO
          )
        ORDER BY PN.NOMBRE_PROFESION, PL.APPATERNO;

    -- Registro basado en la estructura de la tabla DETALLE_ASIGNACION_MES
    R_DETALLE DETALLE_ASIGNACION_MES%ROWTYPE;

    -- Declaro variables para acumular totales por profesión
    V_TOTAL_ASESORIAS_PROFESION NUMBER(10) := 0;
    V_MONTO_TOTAL_HONORARIOS_PROFESION NUMBER(10, 2) := 0;
    V_MONTO_TOTAL_MOVIL_EXTRA_PROFESION NUMBER(10, 2) := 0;
    V_MONTO_TOTAL_ASIG_TIPOCONT_PROFESION NUMBER(10, 2) := 0;
    V_MONTO_TOTAL_ASIG_PROFESION NUMBER(10, 2) := 0;
    V_MONTO_TOTAL_ASIGNACIONES_PROFESION NUMBER(10, 2) := 0;

    -- Declaro variables adicionales para cálculos individuales
    V_TOTAL_ASESORIAS NUMBER(10) := 0;
    V_TOTAL_HONORARIOS NUMBER(10, 2) := 0;
    V_MONTO_MOVIL_EXTRA NUMBER(10, 2) := 0;
    V_MONTO_ASIG_TIPOCONT NUMBER(10, 2) := 0;
    V_MONTO_ASIG_PROFESION NUMBER(10, 2) := 0;
    V_MONTO_TOTAL_ASIGNACIONES NUMBER(10, 2) := 0;
    V_COMUNA VARCHAR2(20);
    V_PORCENTAJE_PROFESION NUMBER(5, 2) := 0;
    V_INCENTIVO NUMBER(5, 2) := 0;

    -- Declaro variables para la tabla de errores
    V_ERROR_MSG VARCHAR2(4000);
    V_ERROR_ID NUMBER := 1;

BEGIN
    -- Limpio las tablas antes de insertar datos
    EXECUTE IMMEDIATE 'TRUNCATE TABLE DETALLE_ASIGNACION_MES'; 
    EXECUTE IMMEDIATE 'TRUNCATE TABLE RESUMEN_MES_PROFESION';
    EXECUTE IMMEDIATE 'TRUNCATE TABLE ERRORES_PROCESO';

    -- Itero sobre todas las profesiones obtenidas con el cursor
    FOR R_RESUMEN_MES_PROF IN C_RESUMEN_MES_PROF LOOP
        -- Inicializo los totales para cada profesión
        V_TOTAL_ASESORIAS_PROFESION := 0;
        V_MONTO_TOTAL_HONORARIOS_PROFESION := 0;
        V_MONTO_TOTAL_MOVIL_EXTRA_PROFESION := 0;
        V_MONTO_TOTAL_ASIG_TIPOCONT_PROFESION := 0;
        V_MONTO_TOTAL_ASIG_PROFESION := 0;
        V_MONTO_TOTAL_ASIGNACIONES_PROFESION := 0;

        -- Itero sobre los profesionales de la profesión actual
        FOR R_DETALLE_ASIG_MES IN C_DETALLE_ASIG_MES(R_RESUMEN_MES_PROF.NOMBRE_PROFESION) LOOP
            BEGIN
                -- Calculo el número de asesorías del profesional actual
                SELECT COUNT(DISTINCT A.COD_EMPRESA || A.INICIO_ASESORIA || A.FIN_ASESORIA)
                INTO V_TOTAL_ASESORIAS
                FROM ASESORIA A
                WHERE A.NUMRUN_PROF = R_DETALLE_ASIG_MES.NUMRUN_PROF
                  AND TO_CHAR(A.INICIO_ASESORIA, 'MM/YYYY') = :FECHA_PROCESO;

                -- Calculo el monto total de honorarios del profesional actual
                SELECT NVL(SUM(A.HONORARIO), 0)
                INTO V_TOTAL_HONORARIOS
                FROM ASESORIA A
                WHERE A.NUMRUN_PROF = R_DETALLE_ASIG_MES.NUMRUN_PROF
                  AND TO_CHAR(A.INICIO_ASESORIA, 'MM/YYYY') = :FECHA_PROCESO;

                -- Obtengo el porcentaje de incentivo por tipo de contrato
                SELECT INCENTIVO
                INTO V_INCENTIVO
                FROM TIPO_CONTRATO
                WHERE COD_TPCONTRATO = R_DETALLE_ASIG_MES.COD_TPCONTRATO;

                -- Calculo el monto asignado por tipo de contrato
                V_MONTO_ASIG_TIPOCONT := V_TOTAL_HONORARIOS * (V_INCENTIVO / 100);

                -- Intento obtener el porcentaje de asignación profesional
                BEGIN
                    SELECT ASIGNACION
                    INTO V_PORCENTAJE_PROFESION
                    FROM PORCENTAJE_PROFESION
                    WHERE COD_PROFESION = R_DETALLE_ASIG_MES.COD_PROFESION;
                    V_MONTO_ASIG_PROFESION := V_TOTAL_HONORARIOS * (V_PORCENTAJE_PROFESION / 100);
                EXCEPTION
                    -- Si ocurre un error, asigno 0 y registro el error
                    WHEN OTHERS THEN
                        V_MONTO_ASIG_PROFESION := 0;
                        V_ERROR_MSG := SQLERRM;
                        INSERT INTO ERRORES_PROCESO VALUES (
                            V_ERROR_ID,
                            V_ERROR_MSG,
                            'Error al calcular asignación profesional. RUN: ' || R_DETALLE_ASIG_MES.NUMRUN_PROF
                        );
                        V_ERROR_ID := V_ERROR_ID + 1;
                END;

                -- Obtengo el nombre de la comuna del profesional
                SELECT NOM_COMUNA
                INTO V_COMUNA
                FROM COMUNA
                WHERE COD_COMUNA = R_DETALLE_ASIG_MES.COD_COMUNA;

                -- Calculo el monto de movilización extra según la comuna
                V_MONTO_MOVIL_EXTRA := 0;
                IF V_COMUNA = 'Santiago' AND V_TOTAL_HONORARIOS < 350000 THEN
                    V_MONTO_MOVIL_EXTRA := V_TOTAL_HONORARIOS * 0.02;
                ELSIF V_COMUNA = 'Ñuñoa' THEN
                    V_MONTO_MOVIL_EXTRA := V_TOTAL_HONORARIOS * 0.04;
                ELSIF V_COMUNA = 'La Reina' AND V_TOTAL_HONORARIOS < 400000 THEN
                    V_MONTO_MOVIL_EXTRA := V_TOTAL_HONORARIOS * 0.05;
                ELSIF V_COMUNA = 'La Florida' AND V_TOTAL_HONORARIOS < 800000 THEN
                    V_MONTO_MOVIL_EXTRA := V_TOTAL_HONORARIOS * 0.07;
                ELSIF V_COMUNA = 'Macul' AND V_TOTAL_HONORARIOS < 680000 THEN
                    V_MONTO_MOVIL_EXTRA := V_TOTAL_HONORARIOS * 0.09;
                END IF;

                -- Calculo el monto total de asignaciones
                V_MONTO_TOTAL_ASIGNACIONES := V_MONTO_ASIG_TIPOCONT + V_MONTO_ASIG_PROFESION + V_MONTO_MOVIL_EXTRA;

                -- Aplico el límite máximo de asignaciones
                IF V_MONTO_TOTAL_ASIGNACIONES > :LIMITE_ASIGNACIONES THEN
                    V_MONTO_TOTAL_ASIGNACIONES := :LIMITE_ASIGNACIONES;
                END IF;

                -- Acumulo los totales de la profesión actual
                V_TOTAL_ASESORIAS_PROFESION := V_TOTAL_ASESORIAS_PROFESION + V_TOTAL_ASESORIAS;
                V_MONTO_TOTAL_HONORARIOS_PROFESION := V_MONTO_TOTAL_HONORARIOS_PROFESION + V_TOTAL_HONORARIOS;
                V_MONTO_TOTAL_MOVIL_EXTRA_PROFESION := V_MONTO_TOTAL_MOVIL_EXTRA_PROFESION + V_MONTO_MOVIL_EXTRA;
                V_MONTO_TOTAL_ASIG_TIPOCONT_PROFESION := V_MONTO_TOTAL_ASIG_TIPOCONT_PROFESION + V_MONTO_ASIG_TIPOCONT;
                V_MONTO_TOTAL_ASIG_PROFESION := V_MONTO_TOTAL_ASIG_PROFESION + V_MONTO_ASIG_PROFESION;
                V_MONTO_TOTAL_ASIGNACIONES_PROFESION := V_MONTO_TOTAL_ASIGNACIONES_PROFESION + V_MONTO_TOTAL_ASIGNACIONES;

                -- Inserto los datos del profesional en la tabla DETALLE_ASIGNACION_MES
                R_DETALLE.MES_PROCESO := 6;
                R_DETALLE.ANNO_PROCESO := 2021;
                R_DETALLE.RUN_PROFESIONAL := R_DETALLE_ASIG_MES.NUMRUN_PROF;
                R_DETALLE.NOMBRE_PROFESIONAL := R_DETALLE_ASIG_MES.NOMBRE_PROF;
                R_DETALLE.PROFESION := R_DETALLE_ASIG_MES.PROFESION;
                R_DETALLE.NRO_ASESORIAS := V_TOTAL_ASESORIAS;
                R_DETALLE.MONTO_HONORARIOS := V_TOTAL_HONORARIOS;
                R_DETALLE.MONTO_ASIG_TIPOCONT := V_MONTO_ASIG_TIPOCONT;
                R_DETALLE.MONTO_ASIG_PROFESION := V_MONTO_ASIG_PROFESION;
                R_DETALLE.MONTO_MOVIL_EXTRA := V_MONTO_MOVIL_EXTRA;
                R_DETALLE.MONTO_TOTAL_ASIGNACIONES := V_MONTO_TOTAL_ASIGNACIONES;

                INSERT INTO DETALLE_ASIGNACION_MES VALUES R_DETALLE;
            END;
        END LOOP;

        -- Inserto el resumen acumulado de la profesión en la tabla RESUMEN_MES_PROFESION
        INSERT INTO RESUMEN_MES_PROFESION (
            ANNO_MES_PROCESO, PROFESION, TOTAL_ASESORIAS, MONTO_TOTAL_HONORARIOS,
            MONTO_TOTAL_MOVIL_EXTRA, MONTO_TOTAL_ASIG_TIPOCONT, MONTO_TOTAL_ASIG_PROF, MONTO_TOTAL_ASIGNACIONES
        ) VALUES (
            202106,
            R_RESUMEN_MES_PROF.NOMBRE_PROFESION,
            V_TOTAL_ASESORIAS_PROFESION,
            V_MONTO_TOTAL_HONORARIOS_PROFESION,
            V_MONTO_TOTAL_MOVIL_EXTRA_PROFESION,
            V_MONTO_TOTAL_ASIG_TIPOCONT_PROFESION,
            V_MONTO_TOTAL_ASIG_PROFESION,
            V_MONTO_TOTAL_ASIGNACIONES_PROFESION
        );
    END LOOP;

    -- Confirmo todos los cambios realizados en las tablas
    COMMIT;
END;

-- Consulto los resultados de las tablas procesadas
SELECT * FROM DETALLE_ASIGNACION_MES;
SELECT * FROM RESUMEN_MES_PROFESION;
SELECT * FROM ERRORES_PROCESO;

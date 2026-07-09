-- Crea las BBDD de gastos y auth en el Postgres compartido (además de la de
-- microworkout, que es la POSTGRES_DB principal). Se ejecuta solo al inicializar
-- el volumen por primera vez. Propietario: el usuario POSTGRES_USER.
CREATE DATABASE gastos;
CREATE DATABASE auth;

-- A sensor-readings application on posit16_1.
--
-- Scenario: sites have sensors, each sensor has a calibration gain, and each reading is a
-- posit. Everything here uses only what the type supports today: comparisons, + - * /,
-- ORDER BY, an index, joins and window functions. There are no aggregates yet.
--
-- Run after install.sql and bind.sql. Each query prints a labelled result.

\pset footer off

CREATE TABLE sensor (
    id    int PRIMARY KEY,
    site  text NOT NULL,
    gain  posit16_1 NOT NULL
);
CREATE TABLE reading (
    id        bigserial PRIMARY KEY,
    sensor_id int NOT NULL REFERENCES sensor (id),
    taken     int NOT NULL,           -- minutes since the start of the day
    raw       posit16_1 NOT NULL
);
CREATE INDEX reading_raw ON reading (raw);

INSERT INTO sensor VALUES (1, 'north', '1.5'), (2, 'south', '0.5');
INSERT INTO reading (sensor_id, taken, raw) VALUES
    (1, 0,   '2'),   (1, 10,  '2.25'), (1, 20, '3'),  (1, 30, '2.5'),
    (2, 0,   '8'),   (2, 10,  '7.5'),  (2, 20, '6'),  (2, 30, '6.25');

\echo '== 1. The three highest raw readings (ORDER BY on the btree opclass)'
SELECT r.sensor_id, r.taken, r.raw
FROM reading r
ORDER BY r.raw DESC
LIMIT 3;

\echo '== 2. Readings in [2, 3) (range filter; the index can serve it)'
SELECT r.sensor_id, r.taken, r.raw
FROM reading r
WHERE r.raw >= '2' AND r.raw < '3'
ORDER BY r.taken, r.sensor_id;

\echo '== 3. Calibrated readings: raw * gain, per sensor'
SELECT s.site, r.taken, r.raw, r.raw * s.gain AS calibrated
FROM reading r
JOIN sensor s ON s.id = r.sensor_id
ORDER BY s.site, r.taken;

\echo '== 4. Change since the previous reading at the same sensor (window function)'
SELECT s.site, r.taken, r.raw,
       r.raw - lag(r.raw) OVER (PARTITION BY r.sensor_id ORDER BY r.taken) AS delta
FROM reading r
JOIN sensor s ON s.id = r.sensor_id
ORDER BY s.site, r.taken;

\echo '== 5. Alerts: readings above 2 after calibration, at the north site'
SELECT s.site, r.taken, r.raw * s.gain AS calibrated
FROM reading r
JOIN sensor s ON s.id = r.sensor_id
WHERE s.site = 'north' AND r.raw * s.gain > '4'
ORDER BY r.taken;

\echo '== 6. Precision: one more than a million, as posit16_1 and as float8'
-- 1000000 is not a posit16_1 value: the nearest one is 983040, and at that magnitude the
-- posit's spacing is too coarse to hold a +1. The float keeps it.
SELECT ('1000000'::posit16_1)::text AS stored_million,
       ('1000000'::posit16_1 + '1'::posit16_1)::text AS posit_sum,
       (1000000::float8 + 1::float8)::text AS float_sum;

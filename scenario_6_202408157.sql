
CREATE TABLE events (
    event_id        SERIAL PRIMARY KEY,
    event_name      VARCHAR(100) NOT NULL,
    available_seats INT NOT NULL CHECK (available_seats >= 0)
);

CREATE TABLE bookings (
    booking_id     SERIAL PRIMARY KEY,
    event_id       INT NOT NULL REFERENCES events(event_id),
    student_number VARCHAR(20) NOT NULL,
    seats          INT NOT NULL CHECK (seats > 0),
    status         VARCHAR(10) NOT NULL DEFAULT 'BOOKED'
                   CHECK (status IN ('BOOKED', 'CANCELLED')),
    booked_at      TIMESTAMP NOT NULL DEFAULT now()
);

INSERT INTO events (event_name, available_seats) VALUES
    ('Career Fair', 100),
    ('Graduation Dinner', 8),
    ('Freshers Welcome Night', 0),
    ('Hackathon Opening', 50);

SELECT * FROM events ORDER BY event_id;

-- 2. IF / ELSIF / ELSE

DO $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN SELECT event_name, available_seats FROM events ORDER BY event_id LOOP
        IF rec.available_seats = 0 THEN
            RAISE NOTICE '% -> FULL', rec.event_name;
        ELSIF rec.available_seats <= 10 THEN
            RAISE NOTICE '% -> NEARLY FULL (% seats)', rec.event_name, rec.available_seats;
        ELSE
            RAISE NOTICE '% -> PLENTY OF SEATS (%)', rec.event_name, rec.available_seats;
        END IF;
    END LOOP;
END $$;

-- 3. WHILE (booking reminder days) and numeric FOR (entrance checks)

DO $$
DECLARE
    day_no INT := 1;
BEGIN
    WHILE day_no <= 3 LOOP
        RAISE NOTICE 'Booking reminder day %', day_no;
        day_no := day_no + 1;
    END LOOP;

    FOR check_no IN 1..3 LOOP
        RAISE NOTICE 'Entrance check number %', check_no;
    END LOOP;
END $$;

-- 4. book_seats procedure
--    Checks availability, reduces remaining seats, records a booking

CREATE OR REPLACE PROCEDURE book_seats(
    p_event_id       INT,
    p_student_number VARCHAR,
    p_seats          INT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_available INT;
BEGIN
    IF p_seats IS NULL OR p_seats <= 0 THEN
        RAISE EXCEPTION 'Invalid number of seats: % (must be greater than zero)', p_seats
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    SELECT available_seats INTO v_available
    FROM events
    WHERE event_id = p_event_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Event % does not exist', p_event_id;
    END IF;

    IF v_available < p_seats THEN
        RAISE NOTICE 'BOOKING REJECTED: event % has % seats but % requested',
            p_event_id, v_available, p_seats;
        RETURN;
    END IF;

    UPDATE events
    SET available_seats = available_seats - p_seats
    WHERE event_id = p_event_id;

    INSERT INTO bookings (event_id, student_number, seats, status)
    VALUES (p_event_id, p_student_number, p_seats, 'BOOKED');

    RAISE NOTICE 'BOOKING RECORDED: student % booked % seat(s) for event %',
        p_student_number, p_seats, p_event_id;
END;
$$;

-- 5. Two valid bookings and one request exceeding remaining seats

CALL book_seats(1, 'STU001', 4);   
CALL book_seats(2, 'STU002', 5);   
CALL book_seats(2, 'STU003', 6);   

SELECT * FROM events ORDER BY event_id;
SELECT * FROM bookings ORDER BY booking_id;

-- 6. cancel_booking procedure
--    Releases seats and marks booking cancelled (only once)

CREATE OR REPLACE PROCEDURE cancel_booking(p_booking_id INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_event_id INT;
    v_seats    INT;
    v_status   VARCHAR(10);
BEGIN
    SELECT event_id, seats, status
    INTO v_event_id, v_seats, v_status
    FROM bookings
    WHERE booking_id = p_booking_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE NOTICE 'Booking % does not exist', p_booking_id;
        RETURN;
    END IF;

    IF v_status = 'CANCELLED' THEN
        RAISE NOTICE 'Booking % was already cancelled. No seats released.', p_booking_id;
        RETURN;
    END IF;

    UPDATE bookings SET status = 'CANCELLED' WHERE booking_id = p_booking_id;

    UPDATE events
    SET available_seats = available_seats + v_seats
    WHERE event_id = v_event_id;

    RAISE NOTICE 'Booking % cancelled. % seat(s) released to event %',
        p_booking_id, v_seats, v_event_id;
END;
$$;

CALL cancel_booking(2);   
CALL cancel_booking(2);   

SELECT * FROM events ORDER BY event_id;
SELECT * FROM bookings ORDER BY booking_id;


-- 7. Explicit cursor: full or nearly full events (10 or fewer seats)

DO $$
DECLARE
    cur_tight_events CURSOR FOR
        SELECT event_id, event_name, available_seats
        FROM events
        WHERE available_seats <= 10
        ORDER BY available_seats, event_id;
    rec RECORD;
BEGIN
    OPEN cur_tight_events;
    LOOP
        FETCH cur_tight_events INTO rec;
        EXIT WHEN NOT FOUND;
        IF rec.available_seats = 0 THEN
            RAISE NOTICE '[%] % is FULL', rec.event_id, rec.event_name;
        ELSE
            RAISE NOTICE '[%] % is NEARLY FULL (% seats left)',
                rec.event_id, rec.event_name, rec.available_seats;
        END IF;
    END LOOP;
    CLOSE cur_tight_events;
END $$;

-- 8. Book zero seats: handle invalid quantity with EXCEPTION block

DO $$
BEGIN
    CALL book_seats(1, 'STU004', 0);
EXCEPTION
    WHEN invalid_parameter_value THEN
        RAISE NOTICE 'EXCEPTION HANDLED: %', SQLERRM;
    WHEN OTHERS THEN
        RAISE NOTICE 'Unexpected error: %', SQLERRM;
END $$;

SELECT * FROM events ORDER BY event_id;
SELECT * FROM bookings ORDER BY booking_id;

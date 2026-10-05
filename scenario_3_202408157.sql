
CREATE TABLE hostel_rooms (
    room_id          SERIAL PRIMARY KEY,
    room_number      VARCHAR(10) NOT NULL UNIQUE,
    available_spaces INT NOT NULL CHECK (available_spaces >= 0)
);

CREATE TABLE allocations (
    allocation_id  SERIAL PRIMARY KEY,
    room_id        INT NOT NULL REFERENCES hostel_rooms(room_id),
    student_number VARCHAR(20) NOT NULL,
    status         VARCHAR(10) NOT NULL DEFAULT 'ALLOCATED'
                   CHECK (status IN ('ALLOCATED', 'COMPLETED')),
    allocated_at   TIMESTAMP NOT NULL DEFAULT now()
);

INSERT INTO hostel_rooms (room_number, available_spaces) VALUES
    ('A101', 4),
    ('A102', 1),
    ('B201', 0),
    ('B202', 3);

SELECT * FROM hostel_rooms ORDER BY room_id;

-- 2. IF / ELSIF / ELSE

DO $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN SELECT room_number, available_spaces FROM hostel_rooms ORDER BY room_id LOOP
        IF rec.available_spaces = 0 THEN
            RAISE NOTICE 'Room % -> FULL', rec.room_number;
        ELSIF rec.available_spaces = 1 THEN
            RAISE NOTICE 'Room % -> ONE SPACE LEFT', rec.room_number;
        ELSE
            RAISE NOTICE 'Room % -> SEVERAL SPACES (%)', rec.room_number, rec.available_spaces;
        END IF;
    END LOOP;
END $$;

-- 3. WHILE (inspection days) and numeric FOR (room checks)

DO $$
DECLARE
    day_no INT := 1;
BEGIN
    WHILE day_no <= 3 LOOP
        RAISE NOTICE 'Hostel inspection day %', day_no;
        day_no := day_no + 1;
    END LOOP;

    FOR check_no IN 1..3 LOOP
        RAISE NOTICE 'Room check number %', check_no;
    END LOOP;
END $$;

-- 4. allocate_room procedure
--    Checks for a space, reduces availability by one, records allocation
CREATE OR REPLACE PROCEDURE allocate_room(
    p_room_id        INT,
    p_student_number VARCHAR
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_available INT;
BEGIN
    -- Validate student number (NULL or blank)
    IF p_student_number IS NULL OR btrim(p_student_number) = '' THEN
        RAISE EXCEPTION 'Invalid input: student number cannot be blank'
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    SELECT available_spaces INTO v_available
    FROM hostel_rooms
    WHERE room_id = p_room_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Room % does not exist', p_room_id;
    END IF;

    IF v_available < 1 THEN
        RAISE NOTICE 'ALLOCATION REJECTED: room % is full', p_room_id;
        RETURN;
    END IF;

    UPDATE hostel_rooms
    SET available_spaces = available_spaces - 1
    WHERE room_id = p_room_id;

    INSERT INTO allocations (room_id, student_number, status)
    VALUES (p_room_id, btrim(p_student_number), 'ALLOCATED');

    RAISE NOTICE 'ALLOCATION RECORDED: student % allocated to room %',
        p_student_number, p_room_id;
END;
$$;

-- 5. Two valid allocations and one allocation to a full room

CALL allocate_room(1, 'STU001');   
CALL allocate_room(2, 'STU002');   
CALL allocate_room(3, 'STU003');   

SELECT * FROM hostel_rooms ORDER BY room_id;
SELECT * FROM allocations ORDER BY allocation_id;

-- 6. check_out procedure

CREATE OR REPLACE PROCEDURE check_out(p_allocation_id INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_room_id INT;
    v_status  VARCHAR(10);
BEGIN
    SELECT room_id, status
    INTO v_room_id, v_status
    FROM allocations
    WHERE allocation_id = p_allocation_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE NOTICE 'Allocation % does not exist', p_allocation_id;
        RETURN;
    END IF;

    IF v_status = 'COMPLETED' THEN
        RAISE NOTICE 'Allocation % is already complete. No space freed.', p_allocation_id;
        RETURN;
    END IF;

    UPDATE allocations SET status = 'COMPLETED' WHERE allocation_id = p_allocation_id;

    UPDATE hostel_rooms
    SET available_spaces = available_spaces + 1
    WHERE room_id = v_room_id;

    RAISE NOTICE 'Allocation % completed. One space freed in room %',
        p_allocation_id, v_room_id;
END;
$$;

CALL check_out(1);   
CALL check_out(1);   

SELECT * FROM hostel_rooms ORDER BY room_id;
SELECT * FROM allocations ORDER BY allocation_id;

-- 7. Explicit cursor: full or nearly full rooms (1 or fewer spaces)

DO $$
DECLARE
    cur_tight_rooms CURSOR FOR
        SELECT room_id, room_number, available_spaces
        FROM hostel_rooms
        WHERE available_spaces <= 1
        ORDER BY available_spaces, room_id;
    rec RECORD;
BEGIN
    OPEN cur_tight_rooms;
    LOOP
        FETCH cur_tight_rooms INTO rec;
        EXIT WHEN NOT FOUND;
        IF rec.available_spaces = 0 THEN
            RAISE NOTICE 'Room % is FULL', rec.room_number;
        ELSE
            RAISE NOTICE 'Room % is NEARLY FULL (% space left)', rec.room_number, rec.available_spaces;
        END IF;
    END LOOP;
    CLOSE cur_tight_rooms;
END $$;

-- 8. Blank student number: handle invalid input with EXCEPTION block

DO $$
BEGIN
    CALL allocate_room(4, '   ');
EXCEPTION
    WHEN invalid_parameter_value THEN
        RAISE NOTICE 'EXCEPTION HANDLED: %', SQLERRM;
    WHEN OTHERS THEN
        RAISE NOTICE 'Unexpected error: %', SQLERRM;
END $$;

SELECT * FROM hostel_rooms ORDER BY room_id;
SELECT * FROM allocations ORDER BY allocation_id;

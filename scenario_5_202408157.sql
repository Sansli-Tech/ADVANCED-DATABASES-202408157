
CREATE TABLE tools (
    tool_id            SERIAL PRIMARY KEY,
    tool_name          VARCHAR(100) NOT NULL,
    available_quantity INT NOT NULL CHECK (available_quantity >= 0)
);

CREATE TABLE tool_loans (
    loan_id        SERIAL PRIMARY KEY,
    tool_id        INT NOT NULL REFERENCES tools(tool_id),
    student_number VARCHAR(20) NOT NULL,
    quantity       INT NOT NULL CHECK (quantity > 0),
    status         VARCHAR(10) NOT NULL DEFAULT 'ISSUED'
                   CHECK (status IN ('ISSUED', 'RETURNED')),
    issued_at      TIMESTAMP NOT NULL DEFAULT now()
);

INSERT INTO tools (tool_name, available_quantity) VALUES
    ('Claw Hammer', 10),
    ('Vernier Caliper', 2),
    ('Soldering Iron', 0),
    ('Digital Multimeter', 6);

SELECT * FROM tools ORDER BY tool_id;


-- 2. IF / ELSIF / ELSE

DO $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN SELECT tool_name, available_quantity FROM tools ORDER BY tool_id LOOP
        IF rec.available_quantity = 0 THEN
            RAISE NOTICE '% -> UNAVAILABLE', rec.tool_name;
        ELSIF rec.available_quantity <= 2 THEN
            RAISE NOTICE '% -> LOW ON STOCK (%)', rec.tool_name, rec.available_quantity;
        ELSE
            RAISE NOTICE '% -> READILY AVAILABLE (%)', rec.tool_name, rec.available_quantity;
        END IF;
    END LOOP;
END $$;

-- 3. WHILE (safety reminders) and numeric FOR (tool inspections)

DO $$
DECLARE
    counter INT := 1;
BEGIN
    WHILE counter <= 3 LOOP
        RAISE NOTICE 'Workshop safety reminder %', counter;
        counter := counter + 1;
    END LOOP;

    FOR inspection_no IN 1..3 LOOP
        RAISE NOTICE 'Tool inspection number %', inspection_no;
    END LOOP;
END $$;

-- 4. issue_tool procedure

CREATE OR REPLACE PROCEDURE issue_tool(
    p_tool_id        INT,
    p_student_number VARCHAR,
    p_quantity       INT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_available INT;
BEGIN
    IF p_quantity IS NULL OR p_quantity <= 0 THEN
        RAISE EXCEPTION 'Invalid quantity: % (must be greater than zero)', p_quantity
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    SELECT available_quantity INTO v_available
    FROM tools
    WHERE tool_id = p_tool_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Tool % does not exist', p_tool_id;
    END IF;

    IF v_available < p_quantity THEN
        RAISE NOTICE 'LOAN REJECTED: tool % has % available but % requested',
            p_tool_id, v_available, p_quantity;
        RETURN;
    END IF;

    UPDATE tools
    SET available_quantity = available_quantity - p_quantity
    WHERE tool_id = p_tool_id;

    INSERT INTO tool_loans (tool_id, student_number, quantity, status)
    VALUES (p_tool_id, p_student_number, p_quantity, 'ISSUED');

    RAISE NOTICE 'LOAN RECORDED: % unit(s) of tool % issued to student %',
        p_quantity, p_tool_id, p_student_number;
END;
$$;

-- 5. Two valid loans and one request exceeding stock
  

SELECT * FROM tools ORDER BY tool_id;
SELECT * FROM tool_loans ORDER BY loan_id;

-- 6. return_tool procedure
--    Restores stock and marks loan returned (only once)

CREATE OR REPLACE PROCEDURE return_tool(p_loan_id INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_tool_id INT;
    v_qty     INT;
    v_status  VARCHAR(10);
BEGIN
    SELECT tool_id, quantity, status
    INTO v_tool_id, v_qty, v_status
    FROM tool_loans
    WHERE loan_id = p_loan_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE NOTICE 'Loan % does not exist', p_loan_id;
        RETURN;
    END IF;

    IF v_status = 'RETURNED' THEN
        RAISE NOTICE 'Loan % was already returned. No stock added.', p_loan_id;
        RETURN;
    END IF;

    UPDATE tool_loans SET status = 'RETURNED' WHERE loan_id = p_loan_id;

    UPDATE tools
    SET available_quantity = available_quantity + v_qty
    WHERE tool_id = v_tool_id;

    RAISE NOTICE 'Loan % returned. % unit(s) restored to tool %',
        p_loan_id, v_qty, v_tool_id;
END;
$$;

CALL return_tool(1);   
CALL return_tool(1);  

SELECT * FROM tools ORDER BY tool_id;
SELECT * FROM tool_loans ORDER BY loan_id;

-- 7. Explicit cursor: tools with low availability (2 or fewer)

DO $$
DECLARE
    cur_low_tools CURSOR FOR
        SELECT tool_id, tool_name, available_quantity
        FROM tools
        WHERE available_quantity <= 2
        ORDER BY available_quantity, tool_id;
    rec RECORD;
BEGIN
    OPEN cur_low_tools;
    LOOP
        FETCH cur_low_tools INTO rec;
        EXIT WHEN NOT FOUND;
        RAISE NOTICE 'Low availability -> [%] % : % available',
            rec.tool_id, rec.tool_name, rec.available_quantity;
    END LOOP;
    CLOSE cur_low_tools;
END $$;

-- 8. Issue zero tools: handle invalid quantity with EXCEPTION block

DO $$
BEGIN
    CALL issue_tool(1, 'STU004', 0);
EXCEPTION
    WHEN invalid_parameter_value THEN
        RAISE NOTICE 'EXCEPTION HANDLED: %', SQLERRM;
    WHEN OTHERS THEN
        RAISE NOTICE 'Unexpected error: %', SQLERRM;
END $$;


SELECT * FROM tools ORDER BY tool_id;
SELECT * FROM tool_loans ORDER BY loan_id;

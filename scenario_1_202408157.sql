
CREATE TABLE books (
    book_id          SERIAL PRIMARY KEY,
    title            VARCHAR(150) NOT NULL,
    available_copies INT NOT NULL CHECK (available_copies >= 0)
);

CREATE TABLE book_loans (
    loan_id        SERIAL PRIMARY KEY,
    book_id        INT NOT NULL REFERENCES books(book_id),
    student_number VARCHAR(20) NOT NULL,
    quantity       INT NOT NULL CHECK (quantity > 0),
    loan_status    VARCHAR(10) NOT NULL DEFAULT 'BORROWED'
                   CHECK (loan_status IN ('BORROWED', 'RETURNED')),
    loan_date      TIMESTAMP NOT NULL DEFAULT now()
);

INSERT INTO books (title, available_copies) VALUES
    ('Database System Concepts', 5),
    ('Operating System Concepts', 2),
    ('Computer Networks', 0),
    ('Discrete Mathematics', 8);

SELECT * FROM books ORDER BY book_id;

-- 2. IF / ELSIF / ELSE

DO $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN SELECT title, available_copies FROM books ORDER BY book_id LOOP
        IF rec.available_copies = 0 THEN
            RAISE NOTICE '% -> UNAVAILABLE (% copies)', rec.title, rec.available_copies;
        ELSIF rec.available_copies <= 2 THEN
            RAISE NOTICE '% -> LOW ON COPIES (% copies)', rec.title, rec.available_copies;
        ELSE
            RAISE NOTICE '% -> SUFFICIENTLY STOCKED (% copies)', rec.title, rec.available_copies;
        END IF;
    END LOOP;
END $$;

-- 3. WHILE loop (overdue reminders) and numeric FOR loop (shelf numbers)

DO $$
DECLARE
    counter INT := 1;
BEGIN
    WHILE counter <= 3 LOOP
        RAISE NOTICE 'Overdue reminder number: %', counter;
        counter := counter + 1;
    END LOOP;

    FOR shelf IN 1..3 LOOP
        RAISE NOTICE 'Library shelf number: %', shelf;
    END LOOP;
END $$;

-- 4. borrow_book procedure
--    Checks copies, reduces stock and records a loan

CREATE OR REPLACE PROCEDURE borrow_book(
    p_book_id        INT,
    p_student_number VARCHAR,
    p_quantity       INT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_available INT;
BEGIN
    -- Validate quantity
    IF p_quantity IS NULL OR p_quantity <= 0 THEN
        RAISE EXCEPTION 'Invalid quantity: % (must be greater than zero)', p_quantity
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    -- Lock the book row and read available copies
    SELECT available_copies INTO v_available
    FROM books
    WHERE book_id = p_book_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Book % does not exist', p_book_id;
    END IF;

    -- Not enough copies: reject, record nothing
    IF v_available < p_quantity THEN
        RAISE NOTICE 'LOAN REJECTED: book % has % copies but % requested',
            p_book_id, v_available, p_quantity;
        RETURN;
    END IF;

    -- Reduce stock and record the loan
    UPDATE books
    SET available_copies = available_copies - p_quantity
    WHERE book_id = p_book_id;

    INSERT INTO book_loans (book_id, student_number, quantity, loan_status)
    VALUES (p_book_id, p_student_number, p_quantity, 'BORROWED');

    RAISE NOTICE 'LOAN RECORDED: student % borrowed % copy/copies of book %',
        p_student_number, p_quantity, p_book_id;
END;
$$;

-- 5. Two valid loans and one request exceeding available copies

CALL borrow_book(1, 'STU001', 2);   
CALL borrow_book(2, 'STU002', 1);   
CALL borrow_book(2, 'STU003', 5);   

SELECT * FROM books ORDER BY book_id;
SELECT * FROM book_loans ORDER BY loan_id;

-- 6. return_book procedure
--    Marks loan returned and restores copies (only once per loan)

CREATE OR REPLACE PROCEDURE return_book(p_loan_id INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_book_id INT;
    v_qty     INT;
    v_status  VARCHAR(10);
BEGIN
    SELECT book_id, quantity, loan_status
    INTO v_book_id, v_qty, v_status
    FROM book_loans
    WHERE loan_id = p_loan_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE NOTICE 'Loan % does not exist', p_loan_id;
        RETURN;
    END IF;

    -- Already returned: do not restore copies again
    IF v_status = 'RETURNED' THEN
        RAISE NOTICE 'Loan % was already returned. No copies restored.', p_loan_id;
        RETURN;
    END IF;

    UPDATE book_loans SET loan_status = 'RETURNED' WHERE loan_id = p_loan_id;

    UPDATE books
    SET available_copies = available_copies + v_qty
    WHERE book_id = v_book_id;

    RAISE NOTICE 'Loan % returned. % copy/copies restored to book %',
        p_loan_id, v_qty, v_book_id;
END;
$$;

CALL return_book(1);   -- first call: restores copies
CALL return_book(1);   -- second call: must NOT restore copies again

SELECT * FROM books ORDER BY book_id;
SELECT * FROM book_loans ORDER BY loan_id;

-- 7. Explicit cursor: books with few copies remaining (2 or fewer)
DO $$
DECLARE
    cur_low_books CURSOR FOR
        SELECT book_id, title, available_copies
        FROM books
        WHERE available_copies <= 2
        ORDER BY available_copies, book_id;
    rec RECORD;
BEGIN
    OPEN cur_low_books;
    LOOP
        FETCH cur_low_books INTO rec;
        EXIT WHEN NOT FOUND;
        RAISE NOTICE 'Few copies left -> [%] % : % copy/copies',
            rec.book_id, rec.title, rec.available_copies;
    END LOOP;
    CLOSE cur_low_books;
END $$;

-- 8. Borrow zero copies: handle invalid quantity with EXCEPTION block

DO $$
BEGIN
    CALL borrow_book(1, 'STU004', 0);
EXCEPTION
    WHEN invalid_parameter_value THEN
        RAISE NOTICE 'EXCEPTION HANDLED: %', SQLERRM;
    WHEN OTHERS THEN
        RAISE NOTICE 'Unexpected error: %', SQLERRM;
END $$;

SELECT * FROM books ORDER BY book_id;
SELECT * FROM book_loans ORDER BY loan_id;

CREATE DATABASE IF NOT EXISTS payroll_db;
USE payroll_db;

DROP FUNCTION IF EXISTS get_leave_deduction;
DELIMITER $$
CREATE FUNCTION get_leave_deduction(
	emp_ID VARCHAR(255),
    month_ INT,
    year_ YEAR
	
)
RETURNS DECIMAL(10,2)
DETERMINISTIC
BEGIN
	DECLARE leave_deduction DECIMAL(10,2);
-- 	DECLARE last_date DATE;
    DECLARE personal_leave_deduc INT;
-- 	SET last_date = LAST_DAY(DATE(CONCAT_WS('-', year_, month_, 1)));
	SET leave_deduction = 0;
    SELECT deduction_amount INTO personal_leave_deduc FROM leaves WHERE leave_ID = 500;
    
    -- Recursive CTE to get months and years between the start and end date of leave.
    WITH RECURSIVE months_in_leave as (
	  select tl.emp_ID, tl.leave_ID, tl.start_date, tl.end_date, CAST(DATE_FORMAT(tl.start_date ,'%Y-%m-01') as DATE) AS "leave_month"
	  from takes_leave as tl
      WHERE tl.emp_ID = emp_ID and year(tl.start_date)=year_
	  union all
	  select ml.emp_ID, ml.leave_ID, ml.start_date+ interval 1 month, ml.end_date, CAST(DATE_FORMAT(ml.start_date+ interval 1 month ,'%Y-%m-01') as DATE)  AS "leave_month"
	  from months_in_leave as ml 
	  where last_day(ml.start_date) < ml.end_date
	),
    
    -- CTE to get number of leaves taken in the month, year between start and end date of leave.
    leave_days AS (
    SELECT ml.emp_ID, ml.leave_ID, ml.leave_month
    , tl.start_date, tl.end_date,
    CASE 
    WHEN CAST(DATE_FORMAT(tl.start_date ,'%Y-%m-01') as DATE) = CAST(DATE_FORMAT(tl.end_date ,'%Y-%m-01') as DATE) THEN datediff(tl.end_date, tl.start_date)+1
    WHEN ml.leave_month = CAST(DATE_FORMAT(tl.start_date ,'%Y-%m-01') as DATE) THEN datediff(LAST_DAY(tl.start_date),tl.start_date)+1
    WHEN ml.leave_month = CAST(DATE_FORMAT(tl.end_date ,'%Y-%m-01') as DATE) THEN datediff(tl.end_date, CAST(DATE_FORMAT(tl.end_date ,'%Y-%m-01') as DATE))+1 -- DATE_SUB(tl., INTERVAL DAY("2017-06-15")- 1 DAY))+1
    ELSE DAY(LAST_DAY(ml.leave_month))
    END AS "leaves_taken"
	FROM months_in_leave ml
    JOIN takes_leave tl ON ml.emp_ID=tl.emp_ID AND ml.leave_ID=tl.leave_ID AND 
		CAST(DATE_FORMAT(tl.start_date ,'%Y-%m-01') as DATE) <= ml.leave_month AND ml.leave_month <= CAST(DATE_FORMAT(tl.end_date ,'%Y-%m-01') as DATE)
    ORDER BY 1,2,3
    ),
    
    -- Find sum of leaves taken each month for each leave type and employee
    sum_leave_days AS (
		SELECT emp_ID, leave_ID, leave_month, SUM(leaves_taken) AS "month_leaves"
		FROM leave_days
        GROUP BY emp_ID, leave_ID, leave_month
    ),
    
    -- Find cumulative sum of the sum of leaves taken over a month for each employee and leave type
    cum_sum_leave_days AS (
	SELECT *, SUM(month_leaves) OVER(PARTITION BY emp_ID, leave_ID ORDER BY leave_month) AS "cumulative_sum"
    FROM sum_leave_days
    ),
    
    -- CTE to get the previous cumulative sum for 
    lag_cum_sum_leave_days AS (
    SELECT *, LAG(cumulative_sum,1,0) OVER(PARTITION BY emp_ID, leave_ID ORDER BY leave_month) AS "prev_cum_sum"
    FROM cum_sum_leave_days
    )
	
    -- CTE to assign penalty if number of leaves taken are more than the allowance
	,leave_penalty AS(
    SELECT lcs.* , l.days_allowance, l.deduction_amount,

    CASE
		WHEN lcs.cumulative_sum > l.days_allowance THEN
		CASE
			WHEN lcs.prev_cum_sum>=l.days_allowance THEN month_leaves*personal_leave_deduc
            ELSE (l.days_allowance-lcs.prev_cum_sum)*l.deduction_amount + (lcs.cumulative_sum-l.days_allowance)*personal_leave_deduc
		END
		ELSE month_leaves*l.deduction_amount
    END AS 'total_deduc'
    FROM lag_cum_sum_leave_days lcs
    JOIN leaves l ON lcs.leave_ID = l.leave_ID
    )
    
    -- Total deduction per month
	,sum_leave_penalty AS (
		SELECT emp_ID, leave_month, SUM(total_deduc) AS "Monthly_deduc"
		FROM leave_penalty
		GROUP BY emp_ID, leave_month
		ORDER BY emp_ID, leave_month
    )

    -- Return leave deduction for that month else return 0
	SELECT COALESCE((
				SELECT monthly_deduc
				FROM sum_leave_penalty
				WHERE leave_month = str_to_date(CONCAT(CAST(year_ AS CHAR(10)), '-', CAST(month_ AS CHAR(10)),'-', "01"), '%Y-%m-%d')
            ),0) INTO leave_deduction

	;
    RETURN leave_deduction;
END$$
DELIMITER ;

DROP PROCEDURE IF EXISTS get_gross_pay;
DELIMITER $$
-- Gross pay = sum of hourly pay of department, position and grade * number of hours worked in that month - leave deduction
CREATE PROCEDURE get_gross_pay(
	IN emp_ID VARCHAR(255)
    ,IN month_ INT
    ,IN year_ YEAR
    ,IN hrs_worked INT
    ,OUT res DECIMAL(10,2)
)
BEGIN
DECLARE leave_deduction DECIMAL(10,2);
SET leave_deduction = 0;

SELECT (d.dept_pay+p.pos_pay+g.grade_pay)*hrs_worked INTO res
FROM employee e
JOIN department d ON e.dept_ID = d.dept_ID
JOIN positions p ON e.pos_ID = p.pos_ID
JOIN grade g ON e.grade_ID = g.grade_id
WHERE e.emp_ID = emp_ID;

-- CALL get_leave_deduction(emp_ID, month_, year_, leave_deduction);
SET leave_deduction = get_leave_deduction(emp_ID, month_, year_);
SET res = res - IFNULL(leave_deduction,0);
END$$
DELIMITER ;

DROP FUNCTION IF EXISTS get_insurance_deduction;
DELIMITER $$
-- Insurance deduction is the sum of percentage for insurance deduction * gross pay
CREATE FUNCTION get_insurance_deduction(
	emp_ID VARCHAR(255),
    gross_pay DECIMAL(10,2)
)
RETURNS DECIMAL(10,2)
DETERMINISTIC
BEGIN
DECLARE res DECIMAL(10,2);
SET res = 0;

SELECT SUM(insu.percent)/100*gross_pay INTO res
FROM insures insr JOIN insurance insu ON insr.i_type = insu.i_type
WHERE insr.emp_ID = emp_ID
GROUP BY insr.emp_ID;

RETURN res;
END $$
DELIMITER ;

DROP FUNCTION IF EXISTS total_bonus_received;
DELIMITER $$
-- Total bonus is the sum of bonuses received depending upon the month, and joining date. Bonuses apart from joining bonus are given each december.
CREATE FUNCTION total_bonus_received (
    ID VARCHAR(255)
--     ,date_ DATE
    ,month_ INT
    ,year_ YEAR
    )
RETURNS INT 
DETERMINISTIC
BEGIN
    DECLARE bonus INT DEFAULT 0;
    DECLARE tmp_var INT;
    SET tmp_var = 0;
    SET bonus = 0;
    
	-- IF  MONTH(date_) = 12 THEN
    IF month_ = 12 THEN
		SELECT SUM(b.amount) 
		INTO bonus
		FROM bonus_and_benefits as b 
		WHERE b.b_type NOT IN ('Child Care assistance', 'Signing Bonus');

		IF (SELECT has_child FROM employee as e WHERE emp_ID = ID) = TRUE THEN
			SELECT b.amount
			INTO tmp_var
			FROM bonus_and_benefits as b 
			WHERE b.b_type = "Child Care assistance";
		END IF;
	
    SET bonus = bonus + tmp_var;
    SET tmp_var= 0;
    
    IF MONTH((SELECT join_date FROM employee WHERE emp_ID = ID)) = month_ -- MONTH(date_) 
		AND YEAR((SELECT join_date FROM employee WHERE emp_ID = ID)) = year_ THEN -- YEAR(date_) THEN
		SELECT b.amount 
		INTO tmp_var
		FROM bonus_and_benefits as b 
		WHERE b.b_type = 'Signing Bonus'; 
	END IF;
    
    SET bonus = bonus + tmp_var;
    
   END IF;
RETURN bonus;
END $$
DELIMITER ;

DROP FUNCTION IF EXISTS get_retirement_deduction;
DELIMITER $$
-- Retirement deduction gives the monthly deduction that is taken from gross pay for retirement savings. Its calculated based on the type of deduction.
-- If retirement deduction is pre tax, then its the product of gross pay and percent. Else its the product of (gross_pay-taxes) and percent.
CREATE FUNCTION get_retirement_deduction(
	emp_ID VARCHAR(255),
    gross_pay DECIMAL(10,2)
)
RETURNS DECIMAL(10,2)
DETERMINISTIC
BEGIN
DECLARE res DECIMAL(10,2);
SET res = 0;

SELECT r.percent/100*gross_pay INTO res
FROM retirement as r
JOIN employee as e ON r.r_plan = e.r_plan
WHERE e.emp_ID = emp_ID;

RETURN res;
END $$
DELIMITER ;

DROP FUNCTION IF EXISTS get_tax_deduction;
DELIMITER $$
-- Tax deduction is calculated based on each month's gross pay thus the tax slabs are not fixed per employee.
CREATE FUNCTION get_tax_deduction(
	emp_ID VARCHAR(255),
    month_ INT,
    year_ YEAR,
    gross_pay DECIMAL(10,2)
)
RETURNS DECIMAL(10,2)
DETERMINISTIC
BEGIN
DECLARE tax_deduction DECIMAL(10,2);
SET tax_deduction = 0;

SELECT SUM(percent)/100 * gross_pay INTO tax_deduction
FROM tax
WHERE (min_pay<=gross_pay AND (gross_pay<max_pay OR isnull(max_pay))) OR isnull(min_pay);

RETURN tax_deduction;
END $$
DELIMITER ;

DROP PROCEDURE IF EXISTS get_net_pay;
DELIMITER $$
-- Procedure to calculate net pay from gross pay, insurance deduction, bonuses, retirement deduction and taxes.
CREATE PROCEDURE get_net_pay(
	IN emp_ID VARCHAR(255)
    ,IN month_ INT
    ,IN year_ YEAR
    ,IN gross_pay DECIMAL(10,2)
    ,OUT net_pay DECIMAL(10,2)
)
BEGIN
DECLARE insures_deduction DECIMAL(10,2);
DECLARE bonus_deduction DECIMAL(10,2);
DECLARE retirement_deduction DECIMAL(10,2);
DECLARE tax_deduction DECIMAL(10,2);
DECLARE pre_tax_var BOOL;
SET insures_deduction = 0;
SET bonus_deduction = 0;
SET retirement_deduction = 0;
SET tax_deduction = 0;

SET net_pay = 0;

SET tax_deduction = get_tax_deduction(emp_ID, month_, year_, gross_pay);

SELECT r.pre_tax INTO pre_tax_var FROM Employee e JOIN retirement r ON e.r_plan = r.r_plan WHERE e.emp_ID = emp_ID;
IF pre_tax_var = TRUE THEN
	SET retirement_deduction = get_retirement_deduction(emp_ID, gross_pay);
ELSE
	SET retirement_deduction = get_retirement_deduction(emp_ID, gross_pay-tax_deduction); 
END IF;

SET insures_deduction =  get_insurance_deduction(emp_ID, gross_pay);
SET bonus_deduction = total_bonus_received(emp_ID, month_, year_);-- DATE(CONCAT_WS('-', year_, month_, 1)));

SET net_pay = gross_pay - insures_deduction + bonus_deduction - retirement_deduction - tax_deduction ;

END$$
DELIMITER ;


DROP PROCEDURE IF EXISTS insert_payroll_from_attendance;
DELIMITER $$
-- Procedure to insert calculated payroll and taxes in their tables.
CREATE PROCEDURE insert_payroll_from_attendance(
	IN emp_ID VARCHAR(255)
    ,IN month_ INT
    ,IN year_ YEAR
	,IN hrs_worked INT
    ,OUT new_gross_pay DECIMAL(10,2)
    ,OUT new_net_pay DECIMAL(10,2)
    ,OUT retirement_deduction DECIMAL(10,2)
)
BEGIN
	DECLARE tax_deduction DECIMAL(10,2);
	DECLARE pre_tax_var BOOL;
    
    SET new_gross_pay = 0;
    SET new_net_pay = 0;
    
    CALL get_gross_pay(emp_ID, month_, year_, hrs_worked, new_gross_pay);
	-- SET new_gross_pay = get_gross_pay_new(emp_ID, month_, year_, hrs_worked);
    CALL get_net_pay(emp_ID, month_, year_, new_gross_pay, new_net_pay);
	
    SET retirement_deduction=0;
    
    SET tax_deduction = get_tax_deduction(emp_ID, month_, year_, new_gross_pay);
	SELECT r.pre_tax INTO pre_tax_var FROM Employee e JOIN retirement r ON e.r_plan = r.r_plan WHERE e.emp_ID = emp_ID;
	IF pre_tax_var = TRUE THEN
		SET retirement_deduction = IFNULL(get_retirement_deduction(emp_ID, new_gross_pay),0);
	ELSE
		SET retirement_deduction = IFNULL(get_retirement_deduction(emp_ID, new_gross_pay-tax_deduction),0); 
	END IF;

    INSERT INTO Payroll_ VALUES(emp_ID, month_, year_, new_gross_pay, new_net_pay);
END $$
DELIMITER ;

DROP PROCEDURE IF EXISTS drop_payroll;
DELIMITER $$
-- Procedure to drop the payroll and taxes table for given employee, month, year and remove the amount contributed by empployee that month from insurance and retirement savings.
CREATE PROCEDURE drop_payroll(
	IN emp_ID VARCHAR(255)
    ,IN month_ INT
    ,IN year_ YEAR
)
BEGIN
DECLARE gross_pay_var DECIMAL(10,2);
DECLARE tax_sum DECIMAL(10,2);
DECLARE pre_tax_var BOOL;

SELECT gross_pay INTO gross_pay_var FROM payroll_ p WHERE p.emp_ID = emp_ID AND p.month_ = month_ AND p.year_ = year_;

SELECT SUM(tax_amount) INTO tax_sum FROM taxes t WHERE t.emp_ID = emp_ID AND t.month_ = month_ AND t.year_ = year_;

SELECT r.pre_tax INTO pre_tax_var FROM Employee e JOIN retirement r ON e.r_plan = r.r_plan WHERE e.emp_ID = emp_ID;
IF pre_tax_var = TRUE THEN
    UPDATE Employee e JOIN Retirement r ON e.r_plan = r.r_plan
    SET e.amount = e.amount - IFNULL((gross_pay_var * r.percent/100),0)
    WHERE e.emp_ID = emp_ID;
ELSE
    UPDATE Employee e JOIN Retirement r ON e.r_plan = r.r_plan
    SET e.amount = e.amount - IFNULL(((gross_pay_var-tax_sum) * r.percent/100),0)
    WHERE e.emp_ID = emp_ID;
END IF;

UPDATE Insures insr JOIN Insurance insu ON insr.i_type = insu.i_type
SET insr.amount = insr.amount - IFNULL((gross_pay_var * insu.percent/100),0)
WHERE insr.emp_ID = emp_ID;

DELETE FROM payroll_ p
WHERE p.emp_ID = emp_ID AND p.month_ = month_ AND p.year_ = year_;

END $$
DELIMITER ;

-- ---------------------------------- Triggers --------------------------------

DROP TRIGGER IF EXISTS insert_attendance_trigger;
DELIMITER $$
-- Trigger when attendance is recorded for an employee. It inserts the payroll, taxes for that employee for given month, year and increments the insurance and retirement savings by their respective deductions for each employee.
CREATE TRIGGER insert_attendance_trigger AFTER INSERT ON attendance
FOR EACH ROW
BEGIN
	DECLARE new_gross_pay DECIMAL(10,2);
    DECLARE new_net_pay DECIMAL(10,2);
    DECLARE retirement_deduction DECIMAL(10,2);
	CALL insert_payroll_from_attendance(new.emp_ID, new.month_, new.year_, new.hrs_worked, new_gross_pay, new_net_pay, retirement_deduction);
    
	UPDATE insures insr
	JOIN insurance insu ON insr.i_type = insu.i_type
	SET insr.amount = IFNULL(insr.amount,0) + IFNULL((new_gross_pay * insu.percent/100),0)
	WHERE insr.emp_ID = new.emp_ID;
    
	UPDATE employee e
	SET e.amount = IFNULL(e.amount,0) + IFNULL(retirement_deduction,0)
	WHERE e.emp_ID = new.emp_ID;
END $$
DELIMITER ;

DROP TRIGGER IF EXISTS b4_update_attendance_trigger;
DELIMITER $$
-- Trigger for before an update takes place in the attendance table. It deletes the payroll, taxes for the corresponding attendance and removes the amount contributed by empployee that month from insurance and retirement savings.
CREATE TRIGGER b4_update_attendance_trigger BEFORE UPDATE ON Attendance
FOR EACH ROW
BEGIN
	DECLARE old_gross_pay_var DECIMAL(10,2);
    DECLARE old_tax_sum_var DECIMAL(10,2);
    DECLARE old_pre_tax_var BOOL;
    
    SELECT IFNULL(gross_pay,0) INTO old_gross_pay_var FROM payroll_ p WHERE p.emp_ID = old.emp_ID AND p.month_ = old.month_ AND p.year_ = old.year_;

	SELECT IFNULL(SUM(tax_amount),0) INTO old_tax_sum_var FROM taxes t WHERE t.emp_ID = old.emp_ID AND t.month_ = old.month_ AND t.year_ = old.year_;

	SELECT r.pre_tax INTO old_pre_tax_var FROM Employee e JOIN retirement r ON e.r_plan = r.r_plan WHERE e.emp_ID = old.emp_ID;
	IF old_pre_tax_var = TRUE THEN
		UPDATE Employee e JOIN Retirement r ON e.r_plan = r.r_plan
		SET e.amount = IFNULL(e.amount,0) - IFNULL((old_gross_pay_var * r.percent/100),0)
		WHERE e.emp_ID = old.emp_ID;
	ELSE
		UPDATE Employee e JOIN Retirement r ON e.r_plan = r.r_plan
		SET e.amount = IFNULL(e.amount,0) - IFNULL(((old_gross_pay_var-old_tax_sum_var) * r.percent/100),0)
		WHERE e.emp_ID = old.emp_ID;
	END IF;

	UPDATE Insures insr JOIN Insurance insu ON insr.i_type = insu.i_type
	SET insr.amount = IFNULL(insr.amount,0) - IFNULL((old_gross_pay_var * insu.percent/100),0)
	WHERE insr.emp_ID = old.emp_ID;
    
    DELETE FROM payroll_ p
	WHERE p.emp_ID = old.emp_ID AND p.month_ = old.month_ AND p.year_ = old.year_;
    
	END $$
DELIMITER ;

DROP TRIGGER IF EXISTS af_update_attendance_trigger;
DELIMITER $$
-- Trigger that takes place after an attendance update. It inserts the new payroll, taxes and updates insures and retirement savings for respective employee.
CREATE TRIGGER af_update_attendance_trigger AFTER UPDATE ON Attendance
FOR EACH ROW
BEGIN
	DECLARE new_gross_pay DECIMAL(10,2);
    DECLARE new_net_pay DECIMAL(10,2);
    DECLARE retirement_deduction DECIMAL(10,2);
	CALL insert_payroll_from_attendance(new.emp_ID, new.month_, new.year_, new.hrs_worked, new_gross_pay, new_net_pay, retirement_deduction);
    
	UPDATE insures insr
	JOIN insurance insu ON insr.i_type = insu.i_type
	SET insr.amount = IFNULL(insr.amount,0) + IFNULL((new_gross_pay * insu.percent/100),0)
	WHERE insr.emp_ID = new.emp_ID;
    
	UPDATE employee e
	SET e.amount = IFNULL(e.amount,0) + IFNULL(retirement_deduction,0)
	WHERE e.emp_ID = new.emp_ID;
END $$
DELIMITER ;

DROP TRIGGER IF EXISTS delete_attendance_trigger;
DELIMITER $$
-- Trigger that handles the deletion of payroll, and modification of insurance and retirement savings.
CREATE TRIGGER delete_attendance_trigger BEFORE DELETE ON Attendance
FOR EACH ROW
BEGIN
	CALL drop_payroll(old.emp_ID, old.month_, old.year_);
END $$
DELIMITER ;

DROP TRIGGER IF EXISTS insert_payroll_trigger;
DELIMITER $$
-- Trigger that calculates taxes for each payroll inserted.
CREATE TRIGGER insert_payroll_trigger AFTER INSERT ON Payroll_
FOR EACH ROW
BEGIN
	INSERT INTO Taxes
	SELECT NEW.emp_ID, NEW.month_, NEW.year_, name, percent/100 * NEW.gross_pay
	FROM Tax
	WHERE (min_pay<=NEW.gross_pay AND (NEW.gross_pay<max_pay OR isnull(max_pay))) OR isnull(min_pay);
END $$
DELIMITER ;

DROP TRIGGER IF EXISTS delete_payroll_trigger;
DELIMITER $$
-- Trigger that deletes taxes for each payroll deleted.
CREATE TRIGGER delete_payroll_trigger BEFORE DELETE ON payroll_
FOR EACH ROW
BEGIN
	DELETE FROM Taxes t
	WHERE t.emp_ID = old.emp_ID AND t.month_ = old.month_ AND t.year_ = old.year_;
END $$
DELIMITER ;

DROP TRIGGER IF EXISTS insert_takes_leave_trigger;
DELIMITER $$
-- Trigger that handles the modification of attendance, payroll, insurance and retirement savings for each month in the leave inserted.
CREATE TRIGGER insert_takes_leave_trigger AFTER INSERT ON takes_leave
FOR EACH ROW
BEGIN
	UPDATE Attendance a
    SET a.emp_ID = new.emp_ID -- a.days_worked = a.days_worked 
    WHERE a.emp_ID = new.emp_ID
    -- AND str_to_date(CONCAT(CAST(a.year_ AS CHAR(10)), '-', CAST(a.month_ AS CHAR(10)),'-', "01"), '%Y-%m-%d') >= CAST(DATE_FORMAT(new.start_date ,'%Y-%m-01') as DATE)
	-- BETWEEN new.start_date AND new.end_date
	AND CAST(DATE_FORMAT(new.start_date ,'%Y-%m-01') as DATE) <= str_to_date(CONCAT(CAST(a.year_ AS CHAR(10)), '-', CAST(a.month_ AS CHAR(10)),'-', "01"), '%Y-%m-%d')
	AND str_to_date(CONCAT(CAST(a.year_ AS CHAR(10)), '-', CAST(a.month_ AS CHAR(10)),'-', "01"), '%Y-%m-%d') <= CAST(DATE_FORMAT(new.end_date ,'%Y-%m-01') as DATE)
    ;
END $$
DELIMITER ;

DROP TRIGGER IF EXISTS af_update_takes_leave_trigger;
DELIMITER $$
-- Trigger that removes the previous leave and its effect on payroll, taxes, insurance and retirement savings. It then adds new leave and updates others accordingly.
CREATE TRIGGER af_update_takes_leave_trigger AFTER UPDATE ON takes_leave
FOR EACH ROW
BEGIN
	UPDATE Attendance a
    SET a.days_worked = a.days_worked
    WHERE a.emp_ID = old.emp_ID
	AND CAST(DATE_FORMAT(old.start_date ,'%Y-%m-01') as DATE) <= str_to_date(CONCAT(CAST(a.year_ AS CHAR(10)), '-', CAST(a.month_ AS CHAR(10)),'-', "01"), '%Y-%m-%d')
	AND str_to_date(CONCAT(CAST(a.year_ AS CHAR(10)), '-', CAST(a.month_ AS CHAR(10)),'-', "01"), '%Y-%m-%d') <= CAST(DATE_FORMAT(old.end_date ,'%Y-%m-01') as DATE)
    ;
	UPDATE Attendance a
    SET a.days_worked = a.days_worked
    WHERE a.emp_ID = new.emp_ID
	AND CAST(DATE_FORMAT(new.start_date ,'%Y-%m-01') as DATE) <= str_to_date(CONCAT(CAST(a.year_ AS CHAR(10)), '-', CAST(a.month_ AS CHAR(10)),'-', "01"), '%Y-%m-%d')
	AND str_to_date(CONCAT(CAST(a.year_ AS CHAR(10)), '-', CAST(a.month_ AS CHAR(10)),'-', "01"), '%Y-%m-%d') <= CAST(DATE_FORMAT(new.end_date ,'%Y-%m-01') as DATE)
    ;
END $$
DELIMITER ;

DROP TRIGGER IF EXISTS delete_takes_leave_trigger;
DELIMITER $$
-- Trigger that removes the previous leave and its effect on payroll, taxes, insurance and retirement savings.
CREATE TRIGGER delete_takes_leave_trigger AFTER DELETE ON takes_leave
FOR EACH ROW
BEGIN
	UPDATE Attendance a
    SET a.days_worked = a.days_worked
    WHERE a.emp_ID = old.emp_ID
	AND CAST(DATE_FORMAT(old.start_date ,'%Y-%m-01') as DATE) <= str_to_date(CONCAT(CAST(a.year_ AS CHAR(10)), '-', CAST(a.month_ AS CHAR(10)),'-', "01"), '%Y-%m-%d')
	AND str_to_date(CONCAT(CAST(a.year_ AS CHAR(10)), '-', CAST(a.month_ AS CHAR(10)),'-', "01"), '%Y-%m-%d') <= CAST(DATE_FORMAT(old.end_date ,'%Y-%m-01') as DATE)
    ;
END $$
DELIMITER ;
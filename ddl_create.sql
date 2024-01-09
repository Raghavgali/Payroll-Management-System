CREATE DATABASE IF NOT EXISTS payroll_db;
USE payroll_db;

DROP TABLE IF EXISTS Bank_Account;
CREATE TABLE Bank_Account(
   bank_name VARCHAR(255)
  ,acc_type  VARCHAR(255)
  ,PRIMARY KEY(bank_name,acc_type)
);

DROP TABLE IF EXISTS Bonus_and_Benefits;
CREATE TABLE Bonus_and_Benefits(
   b_type VARCHAR(255) NOT NULL PRIMARY KEY
  ,amount INT DEFAULT 0 NOT NULL
);

DROP TABLE IF EXISTS Department;
CREATE TABLE Department(
   dept_ID  VARCHAR(255) NOT NULL PRIMARY KEY
  ,name     VARCHAR(255) NOT NULL
  ,dept_pay DECIMAL(10, 2) NOT NULL DEFAULT 0
);

DROP TABLE IF EXISTS Grade;
CREATE TABLE Grade(
   grade_id  VARCHAR(255) NOT NULL PRIMARY KEY
  ,title     VARCHAR(255) NOT NULL
  ,grade_pay DECIMAL(10,2)  NOT NULL
);

DROP TABLE IF EXISTS Insurance;
CREATE TABLE Insurance(
   i_type  VARCHAR(255) NOT NULL PRIMARY KEY
  ,percent DECIMAL(10,2)  NOT NULL
);

DROP TABLE IF EXISTS Leaves;
CREATE TABLE Leaves(
   leave_ID         INT NOT NULL PRIMARY KEY
  ,name             VARCHAR(255) NOT NULL
  ,deduction_amount DECIMAL(10,2)  NOT NULL
  ,days_allowance   INT  NOT NULL
);

DROP TABLE IF EXISTS Positions;
CREATE TABLE Positions(
   pos_ID  VARCHAR(255) NOT NULL PRIMARY KEY
  ,name    VARCHAR(255) NOT NULL
  ,pos_pay DECIMAL(10,2)  NOT NULL
);

DROP TABLE IF EXISTS Retirement;
CREATE TABLE Retirement(
   r_plan  VARCHAR(255) PRIMARY KEY
  ,percent INT  NOT NULL
  ,pre_tax BOOL NOT NULL
);

DROP TABLE IF EXISTS Tax;
CREATE TABLE Tax(
   name    VARCHAR(255) NOT NULL PRIMARY KEY
  ,percent DECIMAL(10,2) NOT NULL
  ,min_pay DECIMAL(10,2)
  ,max_pay DECIMAL(10,2)
);

DROP TABLE IF EXISTS Employee;
CREATE TABLE Employee(
   emp_ID      VARCHAR(255) PRIMARY KEY
  ,full_name   VARCHAR(255) NOT NULL
  ,gender      VARCHAR(255) NOT NULL
  ,age         INT  NOT NULL
  ,email       VARCHAR(255) NOT NULL
  ,join_date   DATE  NOT NULL
  ,contact_num VARCHAR(10) NOT NULL
  ,has_child   BOOLEAN  NOT NULL
  ,account_num VARCHAR(255) NOT NULL
  ,bank_name   VARCHAR(255) NOT NULL
  ,acc_type    VARCHAR(255) NOT NULL
  ,dept_ID     VARCHAR(255) NOT NULL
  ,pos_ID      VARCHAR(255) NOT NULL
  ,grade_ID    VARCHAR(255) NOT NULL
  ,r_plan      VARCHAR(255) NOT NULL
  ,amount      DECIMAL(10,2)  NOT NULL DEFAULT 0
  ,FOREIGN KEY (bank_name, acc_type) REFERENCES Bank_Account(bank_name, acc_type)
  ,FOREIGN KEY (dept_ID) REFERENCES Department(dept_ID)
  ,FOREIGN KEY (pos_ID) REFERENCES Positions(pos_ID)
  ,FOREIGN KEY (grade_ID) REFERENCES Grade(grade_ID)
  ,FOREIGN KEY (r_plan) REFERENCES Retirement(r_plan)
);

DROP TABLE IF EXISTS Attendance;
CREATE TABLE Attendance(
   emp_ID      VARCHAR(255) 
  ,month_      INT CHECK (month_<13 and month_>0)
  ,year_       YEAR 
  ,days_worked INTEGER  NOT NULL
  ,hrs_worked  INTEGER  NOT NULL
  ,PRIMARY KEY (emp_ID, month_, year_)
  ,FOREIGN KEY (emp_ID) REFERENCES Employee(emp_ID)
  ,CHECK(hrs_worked <= days_worked*24)
);

DROP TABLE IF EXISTS Get_Bonus;
CREATE TABLE Get_Bonus(
   emp_ID VARCHAR(255)
  ,b_type VARCHAR(255)
  ,PRIMARY KEY(emp_ID,b_type)
  ,FOREIGN KEY (emp_ID) REFERENCES Employee(emp_ID)
  ,FOREIGN KEY (b_type) REFERENCES Bonus_and_Benefits(b_type)
);

DROP TABLE IF EXISTS Insures;
CREATE TABLE Insures(
   emp_ID VARCHAR(255)
  ,i_type VARCHAR(255)
  ,amount DECIMAL(10,2)  DEFAULT 0
  ,PRIMARY KEY (emp_ID,i_type)
  ,FOREIGN KEY (emp_ID) REFERENCES Employee(emp_ID)
  ,FOREIGN KEY (i_type) REFERENCES Insurance(i_type)
);

DROP TABLE IF EXISTS Takes_Leave;
CREATE TABLE Takes_Leave(
   emp_ID     VARCHAR(255) NOT NULL
  ,leave_ID   INT  NOT NULL
  ,start_date DATE  NOT NULL
  ,end_date   DATE  NOT NULL
  ,PRIMARY KEY (emp_ID, start_date)
  ,FOREIGN KEY (emp_ID) REFERENCES Employee(emp_ID)
  ,FOREIGN KEY (leave_ID) REFERENCES leaves(leave_ID)
  ,CHECK(end_date >= start_date)
);
    
DROP TABLE IF EXISTS Payroll_;
CREATE TABLE Payroll_(
   emp_ID VARCHAR(255)
  ,month_ INT CHECK (month_<13 and month_>0)
  ,year_  YEAR 
  ,gross_pay DECIMAL(10,2)
  ,net_pay DECIMAL(10,2)
  ,PRIMARY KEY (emp_ID,month_, year_)
  ,FOREIGN KEY (emp_ID) REFERENCES Employee(emp_ID)
);

DROP TABLE IF EXISTS taxes;
CREATE TABLE taxes(
	emp_ID VARCHAR(255)
    ,month_ INT CHECK (month_<13 and month_>0)
    ,year_ YEAR
    ,name VARCHAR(255)
    ,tax_amount DECIMAL(10,2) DEFAULT 0
    ,PRIMARY KEY(emp_ID, month_, year_, name)
    ,FOREIGN KEY(emp_ID,month_,year_) REFERENCES payroll_(emp_ID,month_,year_)
    ,FOREIGN KEY(name) REFERENCES Tax(name)
);

CREATE OR REPLACE VIEW employee_pay AS
SELECT e.emp_ID, e.full_name, a.month_, a.year_, a.days_worked, a.hrs_worked, p.gross_pay, p.net_pay
FROM Employee e
JOIN Attendance a ON a.emp_ID = e.emp_ID
JOIN Payroll_ p ON p.emp_ID = e.emp_ID AND a.month_ = p.month_ AND a.year_ = p.year_;

CREATE OR REPLACE VIEW employee_info AS
SELECT e.emp_ID AS "emp_ID", e.full_name, e.gender, e.age, e.join_date, d.name AS "Department", p.name AS "Position", g.title AS "Grade"
FROM Employee e 
JOIN Department d ON e.dept_ID = d.dept_ID
JOIN Positions p ON e.pos_ID = p.pos_ID
JOIN Grade g ON e.grade_ID = g.grade_ID
ORDER BY e.emp_ID;
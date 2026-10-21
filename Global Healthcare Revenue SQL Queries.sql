-- STEP 1 : CREATE DATABASE

USE master;
GO

IF DB_ID('HealthcareDB') IS NULL
    CREATE DATABASE HealthcareDB;
GO

USE HealthcareDB;
GO

-- STEP 2: CREATE TABLES (no foreign keys yet, so loading is fast)
CREATE TABLE dim_countries (
    country_id INT NOT NULL PRIMARY KEY,
    country NVARCHAR(60), region NVARCHAR(40), currency CHAR(3),
    usd_exchange_rate DECIMAL(10,4), cost_index DECIMAL(5,2));

CREATE TABLE dim_departments (
    department_id INT NOT NULL PRIMARY KEY,
    department_name NVARCHAR(60));

CREATE TABLE dim_diagnoses (
    diagnosis_id INT NOT NULL PRIMARY KEY,
    icd10_code VARCHAR(10), diagnosis_name NVARCHAR(100),
    specialty NVARCHAR(60), severity_weight DECIMAL(4,1));

CREATE TABLE dim_hospitals (
    hospital_id INT NOT NULL PRIMARY KEY,
    hospital_name NVARCHAR(120), hospital_type NVARCHAR(60),
    country_id INT, city NVARCHAR(60), bed_capacity INT,
    established_year INT, ownership NVARCHAR(30));

CREATE TABLE dim_doctors (
    doctor_id INT NOT NULL PRIMARY KEY,
    doctor_name NVARCHAR(100), gender NVARCHAR(10),
    department_id INT, hospital_id INT, specialization NVARCHAR(60),
    experience_years INT, license_no VARCHAR(20));

CREATE TABLE dim_insurance (
    insurance_id INT NOT NULL PRIMARY KEY,
    insurance_name NVARCHAR(100), country_id INT NULL,
    insurance_type NVARCHAR(20), avg_coverage_pct DECIMAL(4,2));

CREATE TABLE dim_procedures (
    procedure_id INT NOT NULL PRIMARY KEY,
    procedure_name NVARCHAR(100), base_cost_usd DECIMAL(12,2),
    is_surgical BIT, cpt_code VARCHAR(10));

CREATE TABLE dim_medicines (
    medicine_id INT NOT NULL PRIMARY KEY,
    medicine_name NVARCHAR(100), drug_class NVARCHAR(60),
    unit_price_usd DECIMAL(12,2));

CREATE TABLE dim_patients (
    patient_id INT NOT NULL PRIMARY KEY,
    full_name NVARCHAR(150), first_name NVARCHAR(80), last_name NVARCHAR(80),
    gender NVARCHAR(10), date_of_birth DATE, age INT,
    blood_group VARCHAR(4), marital_status NVARCHAR(20),
    country_id INT, city NVARCHAR(60), phone NVARCHAR(50), email NVARCHAR(150),
    insurance_id INT, smoker NVARCHAR(3), registration_date DATE);

CREATE TABLE fact_admissions (
    admission_id INT NOT NULL PRIMARY KEY,
    patient_id INT, hospital_id INT, doctor_id INT, department_id INT,
    diagnosis_id INT, admission_type NVARCHAR(20),
    admission_date DATE, discharge_date DATE, length_of_stay_days INT,
    admission_source NVARCHAR(20), discharge_outcome NVARCHAR(30),
    severity_score INT, readmitted_30d NVARCHAR(3));

CREATE TABLE fact_billing (
    invoice_id VARCHAR(15) NOT NULL PRIMARY KEY,
    admission_id INT,
    room_and_procedure_usd DECIMAL(14,2), pharmacy_usd DECIMAL(14,2),
    gross_amount_usd DECIMAL(14,2), discount_usd DECIMAL(14,2),
    tax_usd DECIMAL(14,2), total_billed_usd DECIMAL(14,2),
    insurance_id INT, insurance_covered_usd DECIMAL(14,2),
    patient_payable_usd DECIMAL(14,2),
    currency CHAR(3), exchange_rate DECIMAL(10,4), total_billed_local DECIMAL(16,2),
    invoice_date DATE, payment_status NVARCHAR(20),
    payment_method NVARCHAR(30), due_date DATE);

CREATE TABLE fact_billing_items (
    billing_item_id INT NOT NULL PRIMARY KEY,
    admission_id INT, charge_category NVARCHAR(40), quantity INT,
    procedure_id INT NULL, unit_price_usd DECIMAL(14,2), line_total_usd DECIMAL(14,2));

CREATE TABLE fact_prescriptions (
    prescription_id INT NOT NULL PRIMARY KEY,
    admission_id INT, medicine_id INT, dosage_frequency NVARCHAR(30),
    duration_days INT, quantity INT,
    unit_price_usd DECIMAL(12,2), line_total_usd DECIMAL(14,2));

CREATE TABLE fact_payments (
    payment_id INT NOT NULL PRIMARY KEY,
    invoice_id VARCHAR(15), amount_paid_usd DECIMAL(14,2),
    payment_method NVARCHAR(30), payment_date DATE, transaction_ref VARCHAR(20));

CREATE TABLE fact_insurance_claims (
    claim_id VARCHAR(15) NOT NULL PRIMARY KEY,
    invoice_id VARCHAR(15), admission_id INT, insurance_id INT,
    claim_amount_usd DECIMAL(14,2), approved_amount_usd DECIMAL(14,2),
    claim_status NVARCHAR(30), claim_date DATE,
    settlement_days DECIMAL(6,1) NULL, rejection_reason NVARCHAR(60) NULL);

CREATE TABLE fact_lab_results (
    lab_id INT NOT NULL PRIMARY KEY,
    admission_id INT, test_name NVARCHAR(60), result_value DECIMAL(12,2),
    unit NVARCHAR(20), ref_low DECIMAL(10,2), ref_high DECIMAL(10,2),
    result_flag NVARCHAR(10));
GO

/* ---------------------------------------------------------------------
   STEP 3: BULK LOAD ALL CSV FILES
   >>> Change @path to the folder where you extracted the CSV files <<<
   The folder must end with a backslash. Run this whole step together.
   --------------------------------------------------------------------- */

DECLARE @path NVARCHAR(300) = N'E:\DATA ANALYST\Power BI\Dataset Power BI\Global Healthcare revenue Dashboard\';
DECLARE @t TABLE (id INT IDENTITY, tbl SYSNAME);
INSERT @t (tbl) VALUES
 ('dim_countries'),('dim_departments'),('dim_diagnoses'),('dim_hospitals'),
 ('dim_doctors'),('dim_insurance'),('dim_procedures'),('dim_medicines'),
 ('dim_patients'),('fact_admissions'),('fact_billing'),('fact_billing_items'),
 ('fact_prescriptions'),('fact_payments'),('fact_insurance_claims'),('fact_lab_results');

 DECLARE @i INT = 1, @n INT = (SELECT COUNT(*) FROM @t), @name SYSNAME, @sql NVARCHAR(MAX);
WHILE @i <= @n
BEGIN
    SELECT @name = tbl FROM @t WHERE id = @i;
    SET @sql = N'BULK INSERT dbo.' + QUOTENAME(@name) + N' FROM ''' + @path + @name + N'.csv''
        WITH (FORMAT = ''CSV'', FIRSTROW = 2, FIELDQUOTE = ''"'',
              FIELDTERMINATOR = '','', ROWTERMINATOR = ''0x0a'',
              CODEPAGE = ''65001'', TABLOCK);';
    PRINT 'Loading ' + @name + ' ...';
    EXEC sys.sp_executesql @sql;
    SET @i += 1;
END
GO

/* Self-pay row: patients/billing with insurance_id = 0 are uninsured */
IF NOT EXISTS (SELECT 1 FROM dim_insurance WHERE insurance_id = 0)
    INSERT dim_insurance (insurance_id, insurance_name, country_id, insurance_type, avg_coverage_pct)
    VALUES (0, N'Self-Pay (No Insurance)', NULL, N'Self-Pay', 0.00);
GO

* ---------------------------------------------------------------------
 --  STEP 4: ROW COUNT CHECK (expected counts in the comments)
   --------------------------------------------------------------------- */

SELECT 'dim_countries' AS tbl, COUNT(*) AS rows_loaded FROM dim_countries              -- 10
UNION ALL SELECT 'dim_departments', COUNT(*) FROM dim_departments                      -- 18
UNION ALL SELECT 'dim_diagnoses', COUNT(*) FROM dim_diagnoses                          -- 51
UNION ALL SELECT 'dim_hospitals', COUNT(*) FROM dim_hospitals                          -- 127
UNION ALL SELECT 'dim_doctors', COUNT(*) FROM dim_doctors                              -- 2,500
UNION ALL SELECT 'dim_insurance', COUNT(*) FROM dim_insurance                          -- 42 (41 + self-pay)
UNION ALL SELECT 'dim_procedures', COUNT(*) FROM dim_procedures                        -- 30
UNION ALL SELECT 'dim_medicines', COUNT(*) FROM dim_medicines                          -- 50
UNION ALL SELECT 'dim_patients', COUNT(*) FROM dim_patients                            -- 75,000
UNION ALL SELECT 'fact_admissions', COUNT(*) FROM fact_admissions                      -- 230,000
UNION ALL SELECT 'fact_billing', COUNT(*) FROM fact_billing                            -- 230,000
UNION ALL SELECT 'fact_billing_items', COUNT(*) FROM fact_billing_items                -- 750,882
UNION ALL SELECT 'fact_prescriptions', COUNT(*) FROM fact_prescriptions                -- 417,853
UNION ALL SELECT 'fact_payments', COUNT(*) FROM fact_payments                          -- 211,824
UNION ALL SELECT 'fact_insurance_claims', COUNT(*) FROM fact_insurance_claims          -- 202,956
UNION ALL SELECT 'fact_lab_results', COUNT(*) FROM fact_lab_results;                   -- 321,707
GO

/* ---------------------------------------------------------------------
   STEP 5: FOREIGN KEYS (data loaded, so now enforce relationships)
   --------------------------------------------------------------------- */

ALTER TABLE dim_hospitals        ADD CONSTRAINT FK_hosp_country  FOREIGN KEY (country_id)    REFERENCES dim_countries(country_id);
ALTER TABLE dim_doctors          ADD CONSTRAINT FK_doc_dept      FOREIGN KEY (department_id) REFERENCES dim_departments(department_id);
ALTER TABLE dim_doctors          ADD CONSTRAINT FK_doc_hosp      FOREIGN KEY (hospital_id)   REFERENCES dim_hospitals(hospital_id);
ALTER TABLE dim_insurance        ADD CONSTRAINT FK_ins_country   FOREIGN KEY (country_id)    REFERENCES dim_countries(country_id);
ALTER TABLE dim_patients         ADD CONSTRAINT FK_pat_country   FOREIGN KEY (country_id)    REFERENCES dim_countries(country_id);
ALTER TABLE dim_patients         ADD CONSTRAINT FK_pat_ins       FOREIGN KEY (insurance_id)  REFERENCES dim_insurance(insurance_id);
ALTER TABLE fact_admissions      ADD CONSTRAINT FK_adm_pat       FOREIGN KEY (patient_id)    REFERENCES dim_patients(patient_id);
ALTER TABLE fact_admissions      ADD CONSTRAINT FK_adm_hosp      FOREIGN KEY (hospital_id)   REFERENCES dim_hospitals(hospital_id);
ALTER TABLE fact_admissions      ADD CONSTRAINT FK_adm_doc       FOREIGN KEY (doctor_id)     REFERENCES dim_doctors(doctor_id);
ALTER TABLE fact_admissions      ADD CONSTRAINT FK_adm_dept      FOREIGN KEY (department_id) REFERENCES dim_departments(department_id);
ALTER TABLE fact_admissions      ADD CONSTRAINT FK_adm_dx        FOREIGN KEY (diagnosis_id)  REFERENCES dim_diagnoses(diagnosis_id);
ALTER TABLE fact_billing         ADD CONSTRAINT FK_bill_adm      FOREIGN KEY (admission_id)  REFERENCES fact_admissions(admission_id);
ALTER TABLE fact_billing         ADD CONSTRAINT FK_bill_ins      FOREIGN KEY (insurance_id)  REFERENCES dim_insurance(insurance_id);
ALTER TABLE fact_billing_items   ADD CONSTRAINT FK_item_adm      FOREIGN KEY (admission_id)  REFERENCES fact_admissions(admission_id);
ALTER TABLE fact_billing_items   ADD CONSTRAINT FK_item_proc     FOREIGN KEY (procedure_id)  REFERENCES dim_procedures(procedure_id);
ALTER TABLE fact_prescriptions   ADD CONSTRAINT FK_rx_adm        FOREIGN KEY (admission_id)  REFERENCES fact_admissions(admission_id);
ALTER TABLE fact_prescriptions   ADD CONSTRAINT FK_rx_med        FOREIGN KEY (medicine_id)   REFERENCES dim_medicines(medicine_id);
ALTER TABLE fact_payments        ADD CONSTRAINT FK_pay_inv       FOREIGN KEY (invoice_id)    REFERENCES fact_billing(invoice_id);
ALTER TABLE fact_insurance_claims ADD CONSTRAINT FK_clm_inv      FOREIGN KEY (invoice_id)    REFERENCES fact_billing(invoice_id);
ALTER TABLE fact_insurance_claims ADD CONSTRAINT FK_clm_adm      FOREIGN KEY (admission_id)  REFERENCES fact_admissions(admission_id);
ALTER TABLE fact_insurance_claims ADD CONSTRAINT FK_clm_ins      FOREIGN KEY (insurance_id)  REFERENCES dim_insurance(insurance_id);
ALTER TABLE fact_lab_results     ADD CONSTRAINT FK_lab_adm       FOREIGN KEY (admission_id)  REFERENCES fact_admissions(admission_id);
GO
 

* ---------------------------------------------------------------------
   -- STEP 6: INDEXES (faster joins and Power BI refresh)
   --------------------------------------------------------------------- */
CREATE INDEX IX_adm_patient  ON fact_admissions(patient_id);
CREATE INDEX IX_adm_hospital ON fact_admissions(hospital_id);
CREATE INDEX IX_adm_date     ON fact_admissions(admission_date);
CREATE INDEX IX_adm_dx       ON fact_admissions(diagnosis_id);
CREATE INDEX IX_bill_adm     ON fact_billing(admission_id);
CREATE INDEX IX_item_adm     ON fact_billing_items(admission_id);
CREATE INDEX IX_rx_adm       ON fact_prescriptions(admission_id);
CREATE INDEX IX_pay_inv      ON fact_payments(invoice_id);
CREATE INDEX IX_clm_inv      ON fact_insurance_claims(invoice_id);
CREATE INDEX IX_lab_adm      ON fact_lab_results(admission_id);
GO

/* ---------------------------------------------------------------------
 --  STEP 7: QUICK BUSINESS CHECK (confirms everything joins correctly)
   --------------------------------------------------------------------- */

SELECT TOP 10
    c.country,
    COUNT(DISTINCT a.admission_id)      AS admissions,
    CAST(SUM(b.total_billed_usd) AS DECIMAL(16,2))      AS total_billed_usd,
    CAST(SUM(b.insurance_covered_usd) AS DECIMAL(16,2)) AS insurance_covered_usd
FROM fact_admissions a
JOIN fact_billing   b ON b.admission_id = a.admission_id
JOIN dim_hospitals  h ON h.hospital_id  = a.hospital_id
JOIN dim_countries  c ON c.country_id   = h.country_id
GROUP BY c.country
ORDER BY total_billed_usd DESC;

-- A1. Business question: Who registered most recently?
SELECT TOP 10 patient_id, full_name, gender, age, city, registration_date
FROM dim_patients
ORDER BY registration_date DESC;

-- A2. Female patients above 60 living in India
SELECT p.patient_id, p.full_name, p.age, p.city
FROM dim_patients p
JOIN dim_countries c ON c.country_id = p.country_id
WHERE c.country = 'India' AND p.gender = 'Female' AND p.age > 60
ORDER BY p.age DESC;
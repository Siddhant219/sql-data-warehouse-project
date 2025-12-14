/*
Run targeted data-quality checks against the silver schema. 
Each query returns rows that violate a specific integrity, formatting, date-range, arithmetic or referential rule so ETL issues can be triaged quickly.
*/

-- Check: duplicate or NULL customer business keys (detects key integrity issues)
SELECT
	cst_id,
	COUNT(*) cnt
FROM [DataWarehouse].silver.crm_cust_info
GROUP BY cst_id
HAVING COUNT(*) > 1 OR cst_id IS NULL;

-- Check: customer first names that still contain leading/trailing whitespace (indicates trimming not applied upstream)
SELECT 
	cst_id, cst_firstname
FROM [DataWarehouse].silver.crm_cust_info
WHERE cst_firstname <> TRIM(cst_firstname);

-- Check: customer last names that still contain leading/trailing whitespace
SELECT 
	cst_id, cst_lastname
FROM [DataWarehouse].silver.crm_cust_info
WHERE cst_lastname <> TRIM(cst_lastname);

-- Check: non-canonical or missing gender values requiring investigation
SELECT 
	cst_id, cst_gndr
FROM [DataWarehouse].silver.crm_cust_info
WHERE cst_gndr NOT IN ('Male','Female','Unknown') OR cst_gndr IS NULL;

-- Check: non-canonical or missing marital-status values requiring investigation
SELECT 
	cst_id, cst_marital_status
FROM [DataWarehouse].silver.crm_cust_info
WHERE cst_marital_status NOT IN ('Married','Single','Unknown') OR cst_marital_status IS NULL;

-- Sample: bounded customer extract to assist manual triage
SELECT TOP (50)  -- 50: bounded sample size
	cst_id, cst_key, cst_firstname, cst_lastname, cst_marital_status, cst_gndr, cst_create_date
FROM [DataWarehouse].silver.crm_cust_info;

-- =============================================
-- Products: key, formatting and cost integrity checks
-- =============================================
-- Check: duplicate or NULL product ids (surface lookup/key problems)
SELECT
	prd_id,
	COUNT(*) cnt
FROM [DataWarehouse].silver.crm_prd_info
GROUP BY prd_id
HAVING COUNT(*) > 1 OR prd_id IS NULL;

-- Check: product names that were not trimmed during load
SELECT 
	prd_id, prd_nm
FROM [DataWarehouse].silver.crm_prd_info
WHERE prd_nm <> TRIM(prd_nm);

-- Check: missing product costs
SELECT 
	prd_id, prd_cost
FROM [DataWarehouse].silver.crm_prd_info
WHERE prd_cost IS NULL;

-- Check: negative product costs (indicates upstream data error)
SELECT 
	prd_id, prd_cost
FROM [DataWarehouse].silver.crm_prd_info
WHERE prd_cost < 0;

-- Check: distinct product-line values (validate canonicalization)
SELECT DISTINCT prd_line
FROM [DataWarehouse].silver.crm_prd_info;

-- Check: compare stored prd_end_dt to computed day-before-next-start to detect ordering or off-by-one issues
SELECT 
	prd_id,
	prd_key,
	prd_nm,
	prd_line,
	prd_start_dt,
	prd_end_dt,
	LEAD(prd_start_dt) OVER (PARTITION BY prd_key ORDER BY prd_start_dt) - 1 AS computed_end_dt  -- computed_end_dt = day before next start
FROM [DataWarehouse].silver.crm_prd_info;

-- =============================================
-- Sales details: date sanity and arithmetic consistency
-- =============================================
-- Check: out-of-range or missing order dates (DATE comparisons)
SELECT 
	sls_ord_num, sls_order_dt
FROM [DataWarehouse].silver.crm_sales_details
WHERE sls_order_dt < '1950-01-01'  -- 1950-01-01: lower plausible order date
   OR sls_order_dt > '2050-01-01'  -- 2050-01-01: upper plausible order date
   OR sls_order_dt IS NULL;        -- missing order date needs investigation

-- Check: chronological ordering between order, ship and due dates
SELECT
	sls_ord_num, sls_order_dt, sls_ship_dt, sls_due_dt
FROM [DataWarehouse].silver.crm_sales_details
WHERE (sls_ship_dt IS NOT NULL AND sls_order_dt > sls_ship_dt)
   OR (sls_due_dt IS NOT NULL  AND sls_order_dt > sls_due_dt);

-- Check: arithmetic consistency between sales, quantity and price
SELECT 
	sls_ord_num,
	sls_sales,
	sls_quantity,
	sls_price
FROM [DataWarehouse].silver.crm_sales_details
WHERE sls_sales <> sls_quantity * sls_price
    OR sls_sales IS NULL OR sls_quantity IS NULL OR sls_price IS NULL
    OR sls_sales <= 0 OR sls_quantity <= 0 OR sls_price <= 0
ORDER BY sls_ord_num;

-- =============================================
-- ERP customer AZ12: birthdate sanity and gender canonicalization
-- =============================================
-- Check: implausible birthdates
SELECT DISTINCT bdate
FROM [DataWarehouse].silver.erp_CUST_AZ12
WHERE bdate < '1924-01-01'  -- 1924-01-01: lower birthdate threshold (~100+ years old)
   OR bdate > GETDATE();     -- future birthdates

-- Check: enumerate gender values present for manual review
SELECT DISTINCT gen
FROM [DataWarehouse].silver.erp_cust_az12;

-- Sample: bounded ERP customer extract for triage
SELECT TOP (50)  -- 50: sample size
	CID, BDATE, GEN
FROM [DataWarehouse].silver.erp_cust_az12;

-- =============================================
-- ERP locations: referential and formatting checks
-- =============================================
-- Check: normalized CID must map to a customer key; or it is orphaned
SELECT
	CID,
	REPLACE(TRIM(CID), '-', '') AS normalized_cid,
	CNTRY
FROM [DataWarehouse].silver.erp_LOC_A101
WHERE REPLACE(TRIM(CID), '-', '') NOT IN (SELECT cst_key FROM [DataWarehouse].silver.crm_cust_info);

-- Check: enumerate country values to verify normalization coverage
SELECT DISTINCT CNTRY
FROM [DataWarehouse].silver.erp_LOC_A101;

SELECT TOP (50) CID, CNTRY
FROM [DataWarehouse].silver.erp_LOC_A101;

-- =============================================
-- ERP category mapping: whitespace and value-set checks
-- =============================================
-- Check: categorical columns with unwanted padding (should be trimmed)
SELECT 
	ID, CAT, SUBCAT, MAINTENANCE
FROM [DataWarehouse].silver.erp_PX_CAT_G1V2
WHERE CAT <> TRIM(CAT) 
	OR SUBCAT <> TRIM(SUBCAT) 
	OR MAINTENANCE <> TRIM(MAINTENANCE);

-- Check: enumerate distinct category values for manual validation
SELECT DISTINCT CAT FROM [DataWarehouse].silver.erp_PX_CAT_G1V2;
SELECT DISTINCT SUBCAT FROM [DataWarehouse].silver.erp_PX_CAT_G1V2;
SELECT DISTINCT MAINTENANCE FROM [DataWarehouse].silver.erp_PX_CAT_G1V2;

SELECT TOP (50) * FROM [DataWarehouse].silver.erp_PX_CAT_G1V2;

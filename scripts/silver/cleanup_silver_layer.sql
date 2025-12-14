-- =============================================
-- silver.[crm_cust_info]
-- =============================================

-- CHECK for Nulls or Duplicates in Primary Kety
-- Expectation : No Result

SELECT
	cst_id,
	COUNT(*) cnt
FROM [DataWarehouse].silver.[crm_cust_info]
GROUP BY cst_id
HAVING COUNT(*) > 1 OR cst_id IS NULL

-- CHECK for Unwanted Spaces
--Expectation : No Result

SELECT 
	cst_firstname
FROM [DataWarehouse].silver.[crm_cust_info]
WHERE cst_firstname != TRIM(cst_firstname)
 
SELECT 
	cst_lastname
FROM [DataWarehouse].silver.[crm_cust_info]
WHERE cst_lastname != TRIM(cst_lastname)
  
--CHECK Data Standardization and Consistency
--Expectation : No Result
 
SELECT 
	*
FROM [DataWarehouse].silver.[crm_cust_info]
WHERE cst_gndr NOT IN ('Male','Female','Unknown') or cst_gndr IS NULL


SELECT 
	*
FROM [DataWarehouse].silver.[crm_cust_info]
WHERE cst_marital_status NOT IN ('Married','Single','Unknown') or cst_marital_status IS NULL

select * from  silver.crm_cust_info

-- =============================================
-- silver.[crm_prd_info]
-- =============================================
-- CHECK for Nulls or Duplicates in Primary Kety
-- Expectation : No Result

SELECT
	prd_id,
	COUNT(*) cnt
FROM [DataWarehouse].silver.crm_prd_info
GROUP BY prd_id
HAVING COUNT(*) > 1 OR prd_id IS NULL




-- CHECK for Unwanted Spaces
--Expectation : No Result

SELECT 
	prd_nm
FROM [DataWarehouse].silver.crm_prd_info
WHERE prd_nm != TRIM(prd_nm)
 
-- CHECK for NULLs or Negative Numbers
-- Expectation : No Result

SELECT 
	prd_cost
FROM [DataWarehouse].silver.crm_prd_info
WHERE prd_cost IS NULL
	
SELECT 
	prd_cost
FROM [DataWarehouse].silver.crm_prd_info
WHERE prd_cost < 0
  
--CHECK Data Standardization and Consistency
 
SELECT 
	DISTINCT prd_line
FROM silver.crm_prd_info 

--CHECK for INVALID Date Orders

select * from  silver.crm_prd_info

SELECT 
	 prd_id,
	 prd_key,
	 prd_nm,
	 prd_line,
	 prd_start_dt,
	 prd_end_dt,
	 LEAD(prd_start_dt) OVER (PARTITION BY prd_key ORDER BY prd_start_dt) - 1  AS prd_end_dt
FROM silver.crm_prd_info 

-- =============================================
-- silver.[crm_sales_details]
-- =============================================
--CHECK for invalid dates
SELECT 
      NULLIF(sls_order_dt,0) sls_order_dt
FROM [DataWarehouse].silver.[crm_sales_details]
WHERE sls_order_dt < 19500101
    OR LEN(sls_order_dt) != 8 
    OR sls_order_dt = 0
    OR sls_order_dt > 20500101

--CHECK for invalid date orders

SELECT *
FROM [DataWarehouse].silver.[crm_sales_details]
WHERE sls_order_dt > sls_ship_dt OR sls_order_dt > sls_due_dt

--CHECK data Consistency : Between Sales, Quantity and Price
-->> Sales = Quantity * Price
-->> Values must not be NuLL, zero or negative 

SELECT 
    sls_ord_num      
    , sls_sales
    , sls_quantity
    , sls_price
FROM [DataWarehouse].silver.[crm_sales_details]
WHERE sls_sales != sls_quantity * sls_price
    OR sls_sales IS NULL OR sls_quantity IS NULL OR sls_price IS NULL
    OR sls_sales <= 0 OR sls_quantity <= 0 OR sls_price <= 0
ORDER BY sls_sales,    sls_quantity, sls_price
-- =============================================
-- silver.[erp_cust_az12]
-- =============================================
--Identify out of range
SELECT DISTINCT 
bdate
FROM silver.erp_CUST_AZ12
WHERE BDATE < '1924-01-01' OR bdate > GETDATE()

--Data Standardization & Consistency
SELECT 
	DISTINCT gen
FROM silver.erp_cust_az12

SELECT 
	*
FROM silver.erp_cust_az12
-- =============================================
-- silver.[erp_LOC_A101]
-- =============================================
SELECT
	CID,
	REPLACE(TRIM(CID), '-', ''),
	CNTRY
FROM silver.[erp_LOC_A101]
WHERE REPLACE(TRIM(CID), '-', '') 
NOT IN (SELECT cst_key FROM silver.crm_cust_info)

--Data Standardization & Consistency
SELECT
	distinct
	CNTRY
	--, CASE 
	--	WHEN UPPER(TRIM(CNTRY)) IN ('DE','GERMANY') THEN 'Germany'
	--	WHEN UPPER(TRIM(CNTRY)) IN ('USA','US','UNITED STATES') THEN 'United States'
	--	WHEN TRIM(CNTRY) = '' OR CNTRY IS NULL THEN 'Unknown'
	--	ELSE TRIM(CNTRY)
	--END AS CNTRY 
FROM silver.[erp_LOC_A101]

SELECT * FROM silver.erp_LOC_A101
-- =============================================
-- silver.[erp_PX_CAT_G1V2]
-- =============================================
--CHECK for unwanted spaces
SELECT 
* 
FROM silver.erp_PX_CAT_G1V2
WHERE CAT != TRIM(CAT) 
	OR SUBCAT != TRIM(SUBCAT) 
	OR MAINTENANCE != TRIM(MAINTENANCE) 


--Data Standardization & Consistency
SELECT 
distinct CAT 
FROM silver.erp_PX_CAT_G1V2

SELECT 
distinct SUBCAT 
FROM silver.erp_PX_CAT_G1V2

SELECT 
distinct MAINTENANCE 
FROM silver.erp_PX_CAT_G1V2

SELECT 
*
FROM silver.erp_PX_CAT_G1V2

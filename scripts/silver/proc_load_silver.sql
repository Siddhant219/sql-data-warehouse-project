USE [DataWarehouse]
GO
/****** Object:  StoredProcedure [silver].[load_silver]    Script Date: 14-12-2025 19:45:21 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/*
===============================================================================
Stored Procedure: Load Silver Layer (Bronze -> Silver )
===============================================================================
Script Purpose:
    This stored procedure loads data from the 'bronze' schema to the 'silver' schema 
    It performs the following actions:
    - Truncates the silver tables before loading data.
    - Data Clensing, Standardization and Enhancement is done before loading data

Parameters:
    None. 
	  This stored procedure does not accept any parameters or return any values.

Usage Example:
    EXEC silver.load_silver;
===============================================================================
*/
CREATE OR ALTER PROCEDURE [silver].[load_silver] AS

BEGIN 

	DECLARE @start_time DATETIME, @end_time DATETIME
	DECLARE @batch_start_time DATETIME, @batch_end_time DATETIME

	BEGIN TRY 
	
		SET @batch_start_time = GETDATE();
		PRINT '============================================';
		PRINT 'Loading Silver Layer';
		PRINT '============================================';

		PRINT '--------------------------------------------';
		PRINT 'Loading CRM Tables';
		PRINT '--------------------------------------------';

		SET @start_time = GETDATE();
		PRINT '>> Truncating Table: silver.crm_cust_info';
		TRUNCATE TABLE silver.crm_cust_info;
	
		PRINT '>> Inserting Data Into: silver.crm_cust_info';
		/*
		Loads the latest customer master row per customer from the bronze layer into `silver.crm_cust_info`.
		Normalizes name whitespace, maps single-letter marital-status and gender codes to readable values,
		and preserves the original creation timestamp for the selected row.
		*/
		-- Insert the most-recent record per customer into the silver layer (de-duplicate by cst_id)
		INSERT INTO silver.crm_cust_info (
			cst_id,
			cst_key,
			cst_firstname,
			cst_lastname,
			cst_marital_status,
			cst_gndr,
			cst_create_date
		)
		SELECT 
			cst_id,
			cst_key,
			TRIM(cst_firstname),  -- normalize leading/trailing whitespace from source names
			TRIM(cst_lastname),
			CASE UPPER(TRIM(cst_marital_status))
				WHEN 'S' THEN 'Single'
				WHEN 'M' THEN 'Married'
				ELSE 'Unknown'
			END cst_marital_status,
			CASE UPPER(TRIM(cst_gndr))
				WHEN 'F' THEN 'Female'
				WHEN 'M' THEN 'Male'
				ELSE 'Unknown'
			END cst_gndr,
			cst_create_date
		FROM (
			SELECT
				*, 
				ROW_NUMBER() OVER (PARTITION BY cst_id ORDER BY cst_create_date DESC) flag_last  -- 1: latest row per cst_id
			FROM [DataWarehouse].[bronze].[crm_cust_info]
			WHERE cst_id IS NOT NULL
		) t 
		WHERE flag_last = 1;  -- 1: keep only the most recent row chosen by ROW_NUMBER

		SET @end_time = GETDATE();
		PRINT '>> Load Duration: ' + CAST(DATEDIFF(second, @start_time, @end_time) AS NVARCHAR) + ' seconds';
		PRINT '>> -------------------------';

		SET @start_time = GETDATE();
		PRINT '>> Truncating Table: silver.crm_prd_info';
		TRUNCATE TABLE silver.crm_prd_info;

		PRINT '>> Inserting Data Into: silver.crm_prd_info';
		
		/*
		This script loads and normalizes product metadata from the bronze layer into the silver.crm_prd_info table.
		It extracts a category id from the product key, normalizes the product key, maps product-line codes to readable names,
		ensures costs are non-null, and computes each product-version's end date as the day before the next version.
		*/
		-- Insert normalized product rows from bronze.crm_prd_info into silver.crm_prd_info; transforms keys, maps line codes, ensures non-null cost, and computes version end dates.
		INSERT INTO silver.crm_prd_info (
			   prd_id				
			 , cat_id				
			 , prd_key				
			 , prd_nm				
			 , prd_cost				
			 , prd_line				
			 , prd_start_dt			
			 , prd_end_dt			
		)
		SELECT 
			 prd_id,
			 REPLACE(SUBSTRING(prd_key, 1, 5), '-', '_') AS cat_id,  -- 5: length of category segment
			 SUBSTRING(prd_key, 7, LEN(prd_key)) AS prd_key,  -- 7: starting position of product segment
			 prd_nm,
			 ISNULL(prd_cost, 0) AS prd_cost,  -- 0: default cost when source prd_cost is NULL
			 CASE UPPER(TRIM(prd_line))  -- Map single-letter product-line codes to descriptive names
				WHEN 'M' THEN 'Mountain'
				WHEN 'R' THEN 'Road'
				WHEN 'T' THEN 'Touring'
				WHEN 'S' THEN 'Other Sales'
				ELSE 'Unknown'
			 END prd_line,
			 CAST(prd_start_dt AS DATE) AS prd_start_dt,
			 CAST(
				LEAD(prd_start_dt) OVER (PARTITION BY prd_key ORDER BY prd_start_dt) - 1  -- 1: subtract one day so end_date is the day before next start
				AS DATE
				) AS prd_end_dt
		FROM bronze.crm_prd_info;

		SET @end_time = GETDATE();
		PRINT '>> Load Duration: ' + CAST(DATEDIFF(second, @start_time, @end_time) AS NVARCHAR) + ' seconds';
		PRINT '>> -------------------------';
		
		SET @start_time = GETDATE();
		PRINT '>> Truncating Table: silver.crm_sales_details';
		TRUNCATE TABLE silver.crm_sales_details;

		PRINT '>> Inserting Data Into: silver.crm_sales_details';
		
		/*
		Cleans and loads sales detail rows from the bronze layer into `silver.crm_sales_details`.
		Dates are validated and converted from integer YYYYMMDD; sales and unit price are recalculated when values are missing or inconsistent so downstream reporting is reliable.
		*/
		-- Insert cleansed sales detail rows into the silver layer (normalize dates, fix sales/price mismatches)
		INSERT INTO silver.crm_sales_details (
		    sls_ord_num,
		    sls_prd_key,
		    sls_cust_id,
		    sls_order_dt,
		    sls_ship_dt,
		    sls_due_dt,
		    sls_sales,
		    sls_quantity,
		    sls_price
		)
		SELECT
		    sls_ord_num,
		    sls_prd_key,
		    sls_cust_id,
		    CASE
		        WHEN sls_order_dt = 0 OR LEN(CAST(sls_order_dt AS VARCHAR(10))) <> 8 THEN NULL  -- 0: sentinel; 8: expected YYYYMMDD length
		        ELSE CAST(CAST(sls_order_dt AS VARCHAR(10)) AS DATE)
		    END AS sls_order_dt,
		    CASE
		        WHEN sls_ship_dt = 0 OR LEN(CAST(sls_ship_dt AS VARCHAR(10))) <> 8 THEN NULL  -- 0: sentinel; 8: expected YYYYMMDD length
		        ELSE CAST(CAST(sls_ship_dt AS VARCHAR(10)) AS DATE)
		    END AS sls_ship_dt,
		    CASE
		        WHEN sls_due_dt = 0 OR LEN(CAST(sls_due_dt AS VARCHAR(10))) <> 8 THEN NULL  -- 0: sentinel; 8: expected YYYYMMDD length
		        ELSE CAST(CAST(sls_due_dt AS VARCHAR(10)) AS DATE)
		    END AS sls_due_dt,
		    CASE
		        WHEN sls_price IS NULL OR sls_price <= 0 OR sls_price <> sls_quantity * ABS(sls_price)
		            THEN sls_quantity * ABS(sls_price)  -- recalc sales when price missing/invalid or inconsistent with quantity
		        ELSE sls_sales
		    END AS sls_sales,
		    sls_quantity,
		    CASE
		        WHEN sls_price IS NULL OR sls_price <= 0 THEN sls_sales / NULLIF(sls_quantity, 0)  -- avoid divide by zero
		        ELSE sls_price
		    END AS sls_price
		FROM bronze.crm_sales_details;

		SET @end_time = GETDATE();
		PRINT '>> Load Duration: ' + CAST(DATEDIFF(second, @start_time, @end_time) AS NVARCHAR) + ' seconds';
		PRINT '>> -------------------------';


		PRINT '--------------------------------------------';
		PRINT 'Loading ERP Tables';
		PRINT '--------------------------------------------';
		
		SET @start_time = GETDATE();
		PRINT '>> Truncating Table: silver.erp_CUST_AZ12';
		TRUNCATE TABLE silver.erp_CUST_AZ12;

		PRINT '>> Inserting Data Into: silver.erp_CUST_AZ12';
		
		/*
		Standardizes customer identifiers, birthdates and gender values as data moves from bronze to silver.
		Removes a leading 'NAS' prefix from `CID` when present, nulls implausible future birthdates, and normalizes gender codes to 'Male'/'Female'/'Unknown'.
		*/
		-- Insert cleaned customer rows from bronze.erp_CUST_AZ12 into silver.erp_CUST_AZ12
		INSERT INTO silver.erp_CUST_AZ12 (
		    CID,
		    BDATE,
		    GEN
		)
		SELECT
		    CASE
		        WHEN CID LIKE 'NAS%' THEN SUBSTRING(CID, 4, LEN(CID))  -- 4: start position to strip leading 'NAS' prefix
		        ELSE CID
		    END AS CID,
		    CASE
		        WHEN BDATE > GETDATE() THEN NULL  -- future birthdates are treated as invalid
		        ELSE BDATE
		    END AS BDATE,
		    CASE
		        WHEN UPPER(TRIM(GEN)) IN ('M','MALE') THEN 'Male'
		        WHEN UPPER(TRIM(GEN)) IN ('F','FEMALE') THEN 'Female'
		        ELSE 'Unknown'
		    END AS GEN
		FROM bronze.erp_CUST_AZ12;

		SET @end_time = GETDATE();
		PRINT '>> Load Duration: ' + CAST(DATEDIFF(second, @start_time, @end_time) AS NVARCHAR) + ' seconds';
		PRINT '>> -------------------------';


		SET @start_time = GETDATE();
		PRINT '>> Truncating Table: silver.erp_LOC_A101';
		TRUNCATE TABLE silver.erp_LOC_A101;

		PRINT '>> Inserting Data Into: silver.erp_LOC_A101';
		
		/* 
		Standardizes location identifiers and country names as data moves from bronze to silver. 
		Removes hyphens from CID, normalizes common country codes/aliases to canonical names, 
		and maps empty or missing country to 'Unknown'. 
		*/ 
		-- Insert cleaned location rows from bronze.erp_LOC_A101 into silver.erp_LOC_A101 
		 
		INSERT INTO silver.[erp_LOC_A101] ( 
			CID, 
			CNTRY 
		) 
		 
		SELECT 
			REPLACE(TRIM(CID), '-', '') AS CID,  -- remove hyphens from identifier 
			CASE 
				WHEN UPPER(TRIM(CNTRY)) IN ('DE','GERMANY') THEN 'Germany'  -- map common DE variants 
				WHEN UPPER(TRIM(CNTRY)) IN ('USA','US','UNITED STATES') THEN 'United States'  -- map common US variants 
				WHEN TRIM(CNTRY) = '' OR CNTRY IS NULL THEN 'Unknown'  -- empty string or NULL -> Unknown 
				ELSE TRIM(CNTRY) 
			END AS CNTRY 
		FROM bronze.[erp_LOC_A101];

		SET @end_time = GETDATE();
		PRINT '>> Load Duration: ' + CAST(DATEDIFF(second, @start_time, @end_time) AS NVARCHAR) + ' seconds';
		PRINT '>> -------------------------';


		SET @start_time = GETDATE();
		PRINT '>> Truncating Table: silver.erp_PX_CAT_G1V2';
		TRUNCATE TABLE silver.erp_PX_CAT_G1V2;

		PRINT '>> Inserting Data Into: silver.erp_PX_CAT_G1V2';

		
		-- Insert cleaned location rows from bronze.erp_PX_CAT_G1V2 into silver.erp_PX_CAT_G1V2 

		INSERT INTO silver.erp_PX_CAT_G1V2 (
			ID,
			CAT,
			SUBCAT,
			MAINTENANCE
		)
		SELECT 
			ID,
			CAT,
			SUBCAT,
			MAINTENANCE
		FROM bronze.erp_PX_CAT_G1V2

		SET @end_time = GETDATE();
		PRINT '>> Load Duration: ' + CAST(DATEDIFF(second, @start_time, @end_time) AS NVARCHAR) + ' seconds';
		PRINT '>> -------------------------';
		
		SET @batch_end_time = GETDATE();		
		PRINT '>> =========================';
		PRINT '>> Loading Silver Layer is Completed';
		PRINT '>> Total Load Duration: ' + CAST(DATEDIFF(second, @batch_start_time, @batch_end_time) AS NVARCHAR) + ' seconds';
		PRINT '>> =========================';
		
	END TRY

	BEGIN CATCH
		
		PRINT '============================================';
		PRINT 'ERROR OCCURED DURING LOADING SILVER LAYER';
		PRINT 'Error Message: ' + ERROR_MESSAGE();
		PRINT 'Error Number: ' + CAST(ERROR_NUMBER() AS NVARCHAR);
		PRINT 'Error State: ' + CAST(ERROR_STATE() AS NVARCHAR);
		PRINT '============================================';

	END CATCH

END

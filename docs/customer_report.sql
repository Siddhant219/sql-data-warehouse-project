/*
============================================================================
Customer Report
============================================================================
Purpose:
	- This report consolidates key customer metrics and behaviours

Highlights:
	1. Gathers essential fields such as names, ages, and transaction details.
	2. Segments customers into categories (VIP, Regular, New) and age groups.
	3. Aggregates customer-level metrics:
		- total orders
		- total sales
		- total quantity purchased
		- total products
		- lifespan (in months)
	4. Calculates valuable KPIs:
		- recency (months since last order)
		- average order value
		- average monthly spend

============================================================================
*/

CREATE VIEW gold.report_customers AS

/*-------------------------------------------------------------
1) Base Query: Retrieves core columns from tables
--------------------------------------------------------------*/
WITH base_query AS (
	SELECT
	  fs.order_number
	, fs.product_key
	, fs.order_date
	, fs.sales_amount
	, fs.quantity
	, dc.customer_key
	, dc.customer_number
	, CONCAT(dc.first_name, ' ', dc.last_name)						AS customer_name
	, DATEDIFF(YEAR, dc.date_of_birth, GETDATE())					AS age
	FROM gold.fact_sales fs
	LEFT JOIN gold.dim_customers dc
	ON fs.customer_key = dc.customer_key
	WHERE order_date IS NOT NULL
),

/*------------------------------------------------------------------
2) Customer Aggregation: Summarize key metrics at the customer level
-------------------------------------------------------------------*/
customer_aggregation AS (
	SELECT
		  customer_key
		, customer_number
		, customer_name
		, age
		, COUNT(DISTINCT order_number) 								AS total_orders
		, SUM(sales_amount)			  								AS total_sales
		, SUM(quantity)				  								AS total_quantity_purchased
		, COUNT(DISTINCT product_key)  								AS total_products
		, DATEDIFF(MONTH, MIN(order_date), MAX(order_date))			AS customer_lifespan
		, DATEDIFF(MONTH, MAX(order_date), GETDATE())				AS customer_recency
	FROM base_query
	GROUP BY
		  customer_key
		, customer_number
		, customer_name
		, age
)


SELECT 
	  customer_key
	, customer_number
	, customer_name
	, age
	, total_orders
	, total_sales
	, total_quantity_purchased
	, total_products
	, customer_lifespan
	, customer_recency
	, CASE 
		WHEN customer_lifespan >= 12 AND total_sales > 5000 THEN 'VIP'
		WHEN customer_lifespan >= 12 AND total_sales <= 5000 THEN 'Regular'
		ELSE 'NEW'
	  END															AS customer_segments
	, CASE 
		  WHEN YEAR(GETDATE()) - age < 1927 THEN 'Greatest Generation' 
		  WHEN YEAR(GETDATE()) - age BETWEEN 1928 AND 1945 THEN 'The Silent Generation' 
		  WHEN YEAR(GETDATE()) - age BETWEEN 1946 AND 1964 THEN 'Baby Boomers' 
		  WHEN YEAR(GETDATE()) - age BETWEEN 1965 AND 1980 THEN 'Generation X'
		  WHEN YEAR(GETDATE()) - age BETWEEN 1981 AND 1996 THEN 'Millennials (Gen Y)' 
		  WHEN YEAR(GETDATE()) - age BETWEEN 1997 AND 2012 THEN 'Generation Z' 
		  ELSE 'Generation Alpha'
	  END															AS generation_cohorts
	  , CASE 
		  WHEN age < 40 THEN 'Below 40' 
		  WHEN age BETWEEN 40 AND 49 THEN '40-49' 
		  WHEN age BETWEEN 50 AND 59 THEN '50-59' 
		  WHEN age BETWEEN 60 AND 69 THEN '60-69' 
		  WHEN age BETWEEN 70 AND 79 THEN '70-79' 
		  ELSE '80 and Above'
	  END															AS age_group
	  , CASE 
			WHEN total_orders = 0 THEN 0
			ELSE ROUND(CAST(total_sales AS FLOAT) / total_orders,2)
		END															AS average_order_value
	  , CASE 
			WHEN customer_lifespan = 0 THEN total_sales
			ELSE ROUND(CAST(total_sales AS FLOAT) / customer_lifespan,2)
		END															AS average_monthly_spend
FROM customer_aggregation


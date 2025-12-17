/*
============================================================================
Product Report
============================================================================
Purpose:
	- This report consolidates key product metrics and behaviours

Highlights:
	1. Gathers essential fields such as product name, category, subcategory and cost.
	2. Segments products by revenue to identify High-Performers, Mid-Range, or Low-Performers
	3. Aggregates product-level metrics:
		- total orders
		- total sales
		- total quantity sold
		- total customers (unique)
		- lifespan (in months)
	4. Calculates valuable KPIs:
		- recency (months since last sale)
		- average order revenue (AOR)
		- average monthly revenue

============================================================================
*/

--CREATE VIEW gold.report_products AS

/*-------------------------------------------------------------
1) Base Query: Retrieves core columns from tables
--------------------------------------------------------------*/

WITH base_query AS (
	SELECT
	  fs.order_number
	, fs.customer_key
	, fs.order_date
	, fs.sales_amount
	, fs.quantity
	, dc.product_key
	, dc.product_name						
	, dc.category
	, dc.subcategory
	, dc.cost
	FROM gold.fact_sales fs
	LEFT JOIN gold.dim_products dc
	ON fs.product_key = dc.product_key
	WHERE order_date IS NOT NULL
),

/*------------------------------------------------------------------
2) Product Aggregation: Summarize key metrics at the product level
-------------------------------------------------------------------*/
product_aggregation AS (
	SELECT
		  product_key
		, product_name
		, category
		, subcategory
		, cost
		, COUNT(DISTINCT order_number) 										AS total_orders
		, SUM(sales_amount)			  										AS total_sales
		, SUM(quantity)				  										AS total_quantity_sold
		, COUNT(DISTINCT customer_key)  									AS total_customers
		, DATEDIFF(MONTH, MIN(order_date), MAX(order_date))					AS product_lifespan
		, DATEDIFF(MONTH, MAX(order_date), GETDATE())						AS product_recency
		, ROUND(AVG(CAST(sales_amount AS FLOAT) / NULLIF(quantity, 0)),1)	AS avg_selling_price
	FROM base_query
	GROUP BY
		  product_key
		, product_name
		, category
		, subcategory
		, cost
)


SELECT 
	  product_key
	, product_name
	, category
	, subcategory
	, cost
	, total_orders
	, total_sales
	, total_quantity_sold
	, total_customers
	, product_lifespan
	, product_recency
	, avg_selling_price
	, CASE 
		WHEN total_sales >= 50000 THEN 'High-Performer'
		WHEN total_sales >= 10000 THEN 'Mid-Range'
		ELSE 'Low_Performer'
	  END															AS product_segments
	, CASE 
		WHEN total_orders = 0 THEN 0
		ELSE ROUND(CAST(total_sales AS FLOAT) / total_orders,2)
	  END															AS average_order_revenue
	, CASE 
		WHEN product_lifespan = 0 THEN total_sales
		ELSE ROUND(CAST(total_sales AS FLOAT) / product_lifespan,2)
	  END															AS average_monthly_revenue
FROM product_aggregation


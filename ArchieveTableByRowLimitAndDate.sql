SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- =============================================
-- Author:		Caner Güven
-- Create date: 2018-12-14
-- Description:	It is archieving the tables by row limit, date month limit parameters
-- Execute  : Exec sp_ArchieveTablesByRowLimit 10000000,12
-- =============================================
ALTER PROCEDURE [dbo].[sp_ArchieveTablesByRowLimit]
	@RowLimit BIGINT =10000000,
	@DateMonthLimit INT = 12
AS 
BEGIN
	SET NOCOUNT ON;

	DECLARE @Today AS NVARCHAR(25)= 'GETDATE()'
	DECLARE @ArchieveTableName NVARCHAR(250) = ''
	DECLARE @TablePKColumnName NVARCHAR(250) = ''
	DECLARE @Query NVARCHAR(MAX) = ''
	DECLARE @TableName NVARCHAR(250)
	DECLARE @SchemaName NVARCHAR(250)
	DECLARE @RowCounts BIGINT

	DECLARE dbCur CURSOR FOR

	SELECT 
		t.NAME AS TableName,
		s.Name AS SchemaName,
		p.rows AS RowCounts
		--CAST(ROUND(((SUM(a.total_pages) * 8) / 1024.00), 2) AS NUMERIC(36, 2)) AS TotalSpaceMB,
		--CAST(ROUND(((SUM(a.used_pages) * 8) / 1024.00), 2) AS NUMERIC(36, 2)) AS UsedSpaceMB, 
		--CAST(ROUND(((SUM(a.total_pages) - SUM(a.used_pages)) * 8) / 1024.00, 2) AS NUMERIC(36, 2)) AS UnusedSpaceMB
	FROM 
		sys.tables t
		INNER JOIN sys.indexes i ON t.OBJECT_ID = i.object_id
		INNER JOIN sys.partitions p ON i.object_id = p.OBJECT_ID AND i.index_id = p.index_id
		INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
		LEFT OUTER JOIN sys.schemas s ON t.schema_id = s.schema_id
	WHERE 
		(t.NAME NOT LIKE 'dt%' AND  t.NAME NOT LIKE '%Archive%'  AND  t.NAME NOT LIKE '%Archieve%')
		AND t.is_ms_shipped = 0
		AND i.OBJECT_ID > 255 
		AND p.rows>@RowLimit 
	GROUP BY 
		t.Name, s.Name, p.Rows
	ORDER BY 
		t.Name

	OPEN dbCur

	FETCH NEXT FROM dbCur INTO @TableName,@SchemaName,@RowCounts

		WHILE @@FETCH_STATUS =0
		BEGIN
		
			BEGIN TRY
				BEGIN TRANSACTION

				SET @ArchieveTableName = ''
				SET @ArchieveTableName = @TableName + '_Archieve'

		
				SELECT 
					 @TablePKColumnName = IsNull(column_name,'')
				FROM 
					 INFORMATION_SCHEMA.TABLE_CONSTRAINTS AS TC
					 INNER JOIN  INFORMATION_SCHEMA.KEY_COLUMN_USAGE AS KU ON TC.CONSTRAINT_TYPE = 'PRIMARY KEY' AND TC.CONSTRAINT_NAME = KU.CONSTRAINT_NAME AND  KU.table_name=@TableName
				ORDER BY 
					 KU.TABLE_NAME, KU.ORDINAL_POSITION;

				SET @Query = ''
				SET @Query = @Query+ @TableName


				SET @Query = @Query + '
				--Step 1

				Select * INTO #Temp 
				From '+@TableName+' 
				Where CreateDate <= DATEADD(month,('+CAST(@DateMonthLimit AS nvarchar)+' * -1),'+@Today+') 
				Order by 1 
				'

				IF (NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = @SchemaName AND  TABLE_NAME = @ArchieveTableName))
				BEGIN
					SET @Query = @Query + '
				--Step 2

				Select Top 0 * into '+ @ArchieveTableName +' from  '+ @TableName

				END
		

				SET @Query = @Query + '

				--Step 3

				INSERT INTO '+@ArchieveTableName+'
				Select * from #Temp Order by 1  '

				--Silme işlemi öncesinde ilgili tablonun relationshiplerinin kaldırılmış olması gerekiyor. Yoksa hata verecektir.
				SET @Query = @Query + ' 

				--Step 4
				DELETE FROM '+@TableName+' WHERE '+@TablePKColumnName+' IN  ( Select '+@TablePKColumnName+' from  '+ @ArchieveTableName +' ) '

				SET @Query = @Query + ' 
		
				--Step 5
				DROP TABLE #Temp
				'
				SET @Query = @Query + '
				--------------------------------------------------------------'

				Print (@Query)

				Exec (@Query)

				COMMIT TRAN
			END TRY
			BEGIN CATCH
				ROLLBACK TRAN
			END CATCH

		FETCH NEXT FROM dbCur INTO @TableName,@SchemaName,@RowCounts
	END

	CLOSE dbCur

	DEALLOCATE dbCur

END


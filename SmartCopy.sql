
DECLARE @TargetSubcatID INT, @SourceSubcatID INT, @SourceActionPackName VARCHAR(500), @Enable_immediately BIT
------------------------------------------------------------------------------------------------------------------------
SET @Enable_immediately = 0 --нужно ли сразу включить действие
SET @SourceSubcatID = 680 -- из какой категории копировать
SET @TargetSubcatID = 809 -- в какую категорию копировать
SET @SourceActionPackName = 'название_пакета' --название пакета
------------------------------------------------------------------------------------------------------------------------

DECLARE @BufferSE TABLE
	(
		ID INT NOT NULL,
		ID_new INT NULL,
		Content VARCHAR(MAX) NOT NULL,
		Name VARCHAR(500) NOT NULL,
		SubcatID INT NULL,
		IsFilter BIT NOT NULL,
		EventID TINYINT NULL,
		ParameterValue INT NULL,
		GUID UNIQUEIDENTIFIER NOT NULL,
		NoContextMode BIT NOT NULL,
		OriginID TINYINT NOT NULL
	)

DECLARE @BufferAP TABLE
	(
		ID INT NOT NULL,
		ID_new INT NULL,
		SubcatID INT NOT NULL,
		Name VARCHAR(500) NOT NULL,
		IsForMailbox BIT NOT NULL,
		GUID UNIQUEIDENTIFIER NOT NULL
	)

DECLARE @BufferPA TABLE
	(
		ID INT NOT NULL,
		ID_new INT NULL,
		ActionsPackID INT NOT NULL,
		ActionsPackID_new INT NULL,
		ActionID TINYINT NULL,
		ActionOrder INT NOT NULL,
		GUID UNIQUEIDENTIFIER NOT NULL,
		CustomActionGUID UNIQUEIDENTIFIER NULL
	)

DECLARE @BufferPAP TABLE
	(
		PackActionID INT NOT NULL,
		PackActionID_new INT NULL,
		ParameterOrder TINYINT NOT NULL,
		Value VARCHAR(MAX) NULL,
		ExpressionID INT NULL,
		ExpressionID_new INT NULL,
		GUID UNIQUEIDENTIFIER NOT NULL,
		PreDefinedParameterID TINYINT NULL
	)

DECLARE @BufferEA TABLE
	(
		ID INT NOT NULL,
		ID_new INT NULL,
		SubcatID INT NOT NULL,
		EventID TINYINT NOT NULL,
		SmartFilterID INT NULL,
		SmartFilterID_new INT NULL,
		ActionsPackID INT NOT NULL,
		ActionsPackID_new INT NULL,
		ParameterValue INT NULL,
		Enabled BIT NOT NULL,
		OrderID TINYINT NOT NULL,
		GUID UNIQUEIDENTIFIER NOT NULL
	)

--заполнение буфера эвент экшенов. enabled = 0 в итоге должно быть
INSERT INTO
	@BufferEA (ID, SubcatID, EventID, SmartFilterID, ActionsPackID, ParameterValue, Enabled, OrderID, GUID)
SELECT
	EA.ID, EA.SubcatID, EventID, SmartFilterID, ActionsPackID, ParameterValue, Enabled, OrderID, EA.GUID
FROM
	EventsActions EA WITH(NOLOCK)
	LEFT JOIN ActionsPacks AP WITH(NOLOCK) ON EA.ActionsPackID = AP.ID
WHERE
	EA.SubcatID = @SourceSubcatID
	AND AP.Name = @SourceActionPackName


--заполнение буфера экшн паков (не глобальных)
INSERT INTO 
	@BufferAP(ID, SubcatID, Name, IsForMailbox, GUID)
SELECT 
	ID, SubcatID, Name, IsForMailbox, GUID
FROM
	ActionsPacks WITH(NOLOCK)
WHERE
	SubcatID = @SourceSubcatID
	AND Name = @SourceActionPackName



--заполнение буфера экшенов в паке (по всем, кроме глобальных)
INSERT INTO
	@BufferPA(ID, ActionsPackID, ActionID, ActionOrder, GUID, CustomActionGUID)
SELECT
	ID, ActionsPackID, ActionID, ActionOrder, GUID, CustomActionGUID
FROM
	PacksActions PA WITH(NOLOCK)
WHERE
	ActionsPackID IN (SELECT ID FROM @BufferAP)


--заполнение буфера параметров экшенов в паке (кроме глобальных)
INSERT INTO
	@BufferPAP(PackActionID, ParameterOrder, Value, ExpressionID, GUID, PreDefinedParameterID)
SELECT
	PackActionID, ParameterOrder, Value, ExpressionID, GUID, PreDefinedParameterID
FROM
	PacksActionsParameters WITH(NOLOCK)
WHERE
	PackActionID IN (SELECT ID FROM @BufferPA)



--заполнение буфера смарт выражений и фильтров (кроме глобальных)
INSERT INTO
	@BufferSE(ID, Content, Name, SubcatID, IsFilter, EventID, ParameterValue, GUID, NoContextMode, OriginID)
SELECT
	ID, Content, Name, SubcatID, IsFilter, EventID, ParameterValue, GUID, NoContextMode, OriginID
FROM
	SmartExpressions WITH(NOLOCK)
WHERE
	SubcatID = @SourceSubcatID
	AND
	(ID IN (SELECT ExpressionID FROM @BufferPAP)
	 OR ID IN (SELECT SmartFilterID FROM @BufferEA))


--Бизнес-логика

DECLARE @ID INT, @SubcatID INT, @Name VARCHAR(500), @IsForMailbox BIT, @GUID UNIQUEIDENTIFIER, @EventID INT, @SmartFilterID INT, @ActionsPackID INT, @ParameterValue INT, @Enabled BIT, @OrderID INT,
@ActionID INT, @ActionOrder INT, @CustomActionGUID UNIQUEIDENTIFIER, @PackActionID INT, @ParameterOrder TINYINT, @Value VARCHAR(MAX), @ExpressionID INT, @PreDefinedParameterID TINYINT, @ActionsPackID_new INT,
@PackActionID_new INT, @Content VARCHAR(MAX), @NoContextMode BIT, @OriginID TINYINT, @ExpressionID_new INT, @SmartFilterID_new INT, @ContextOrderID INT, @IsFilter BIT



BEGIN TRANSACTION tran1
BEGIN TRY
-------------------------------------------------------------------------------------------------------------------------------------------------
DECLARE BufferAP CURSOR FOR
SELECT ID, SubcatID, Name, IsForMailbox, GUID
FROM @BufferAP

--инсерт из буфера экшн паков
OPEN BufferAP
FETCH NEXT FROM BufferAP INTO @ID, @SubcatID, @Name, @IsForMailbox, @GUID
WHILE @@FETCH_STATUS = 0
	BEGIN
		INSERT INTO ActionsPacks (SubcatID, Name, IsForMailbox) VALUES (@TargetSubcatID, @Name, @IsForMailbox)
		UPDATE @BufferAP SET ID_new = SCOPE_IDENTITY() WHERE CURRENT OF BufferAP
		UPDATE @BufferPA SET ActionsPackID_new = SCOPE_IDENTITY() WHERE ActionsPackID = @ID
		UPDATE @BufferEA SET ActionsPackID_new = SCOPE_IDENTITY() WHERE ActionsPackID = @ID
		FETCH NEXT FROM BufferAP INTO @ID, @SubcatID, @Name, @IsForMailbox, @GUID
	END
CLOSE BufferAP
DEALLOCATE BufferAP
----------------------------------------------------------------------------------------------------------------------------------------------
DECLARE BufferPA CURSOR FOR
SELECT ID, ActionsPackID, ActionsPackID_new, ActionID, ActionOrder, GUID, CustomActionGUID
FROM @BufferPA

OPEN BufferPA
FETCH NEXT FROM BufferPA INTO @ID, @ActionsPackID, @ActionsPackID_new, @ActionID, @ActionOrder, @GUID, @CustomActionGUID
WHILE @@FETCH_STATUS = 0
	BEGIN
		INSERT INTO PacksActions(ActionsPackID, ActionID, ActionOrder) VALUES (@ActionsPackID_new, @ActionID, @ActionOrder)
		UPDATE @BufferPA SET ID_new = SCOPE_IDENTITY() WHERE CURRENT OF BufferPA
		UPDATE @BufferPAP SET PackActionID_new = SCOPE_IDENTITY() WHERE PackActionID = @ID
		FETCH NEXT FROM BufferPA INTO @ID, @ActionsPackID, @ActionsPackID_new, @ActionID, @ActionOrder, @GUID, @CustomActionGUID
	END
CLOSE BufferPA
DEALLOCATE BufferPA
------------------------------------------------------------------------------------------------------------------------------------------------
DECLARE BufferSE CURSOR FOR
SELECT ID, Content, Name, SubcatID, IsFilter, EventID, ParameterValue, GUID, NoContextMode, OriginID
FROM @BufferSE

OPEN BufferSE
FETCH NEXT FROM BufferSE INTO @ID, @Content, @Name, @SubcatID, @IsFilter, @EventID, @ParameterValue, @GUID, @NoContextMode, @OriginID
WHILE @@FETCH_STATUS = 0
	BEGIN
	--TODO: Context - parameter value
	INSERT INTO SmartExpressions(Content, Name, SubcatID, IsFilter, EventID, ParameterValue, NoContextMode, OriginID) VALUES (@Content, @Name, @TargetSubcatID, @IsFilter, @EventID, @ParameterValue, @NoContextMode, @OriginID)
	UPDATE @BufferSE SET ID_new = SCOPE_IDENTITY() WHERE CURRENT OF BufferSE
	UPDATE @BufferEA SET SmartFilterID_new = SCOPE_IDENTITY() WHERE SmartFilterID = @ID
	UPDATE @BufferPAP SET ExpressionID_new = SCOPE_IDENTITY() WHERE ExpressionID = @ID

	FETCH NEXT FROM BufferSE INTO @ID, @Content, @Name, @SubcatID, @IsFilter, @EventID, @ParameterValue, @GUID, @NoContextMode, @OriginID
	END
CLOSE BufferSE
DEALLOCATE BufferSE
----------------------------------------------------------------------------------------------------------------------------------------------------------------
DECLARE BufferPAP CURSOR FOR
SELECT PackActionID, PackActionID_new, ParameterOrder, Value, ExpressionID, ExpressionID_new, GUID, PreDefinedParameterID
FROM @BufferPAP

OPEN BufferPAP
FETCH NEXT FROM BufferPAP INTO @PackActionID, @PackActionID_new, @ParameterOrder, @Value, @ExpressionID, @ExpressionID_new, @GUID, @PreDefinedParameterID
WHILE @@FETCH_STATUS = 0
	BEGIN
	INSERT INTO PacksActionsParameters(PackActionID, ParameterOrder, Value, ExpressionID, PreDefinedParameterID) VALUES (@PackActionID_new, @ParameterOrder, @Value, @ExpressionID_new, @PreDefinedParameterID)

	FETCH NEXT FROM BufferPAP INTO @PackActionID, @PackActionID_new, @ParameterOrder, @Value, @ExpressionID, @ExpressionID_new, @GUID, @PreDefinedParameterID
	END
CLOSE BufferPAP
DEALLOCATE BufferPAP
------------------------------------------------------------------------------------------------------------------------------------------------------------



------------------------------------------------------------------------------------------------------------------------------------------------
DECLARE BufferEA CURSOR FOR
SELECT ID, SubcatID, EventID, SmartFilterID, SmartFilterID_new, ActionsPackID, ActionsPackID_new, ParameterValue, Enabled, OrderID, GUID
FROM @BufferEA
ORDER BY OrderID ASC

OPEN BufferEA
FETCH NEXT FROM BufferEA INTO @ID, @SubcatID, @EventID, @SmartFilterID, @SmartFilterID_new, @ActionsPackID, @ActionsPackID_new, @ParameterValue, @Enabled, @OrderID, @GUID
WHILE @@FETCH_STATUS = 0
	BEGIN
	--Calculate OrderID in target subcat context
	SELECT @ContextOrderID = MAX(OrderID) + 1 FROM EventsActions WHERE SubcatID = @TargetSubcatID AND EventID = @EventID
	--Check if global
	IF @SmartFilterID_new IS NULL AND @SmartFilterID IS NOT NULL
		SET @SmartFilterID_new = @SmartFilterID
	IF @ActionsPackID_new IS NULL AND @ActionsPackID IS NOT NULL
		SET @ActionsPackID_new = @ActionsPackID
	--!!TODO: context parameter value
	INSERT INTO EventsActions(SubcatID, EventID, SmartFilterID, ActionsPackID, ParameterValue, Enabled, OrderID) VALUES (@TargetSubcatID, @EventID, @SmartFilterID_new, @ActionsPackID_new, @ParameterValue, @Enable_immediately, @ContextOrderID)

	FETCH NEXT FROM BufferEA INTO @ID, @SubcatID, @EventID, @SmartFilterID, @SmartFilterID_new, @ActionsPackID, @ActionsPackID_new, @ParameterValue, @Enabled, @OrderID, @GUID
	END
CLOSE BufferEA
DEALLOCATE BufferEA
--------------------------------------------------------------------------------------------------------------------------------------------------
COMMIT TRANSACTION tran1
END TRY

BEGIN CATCH
	ROLLBACK TRANSACTION tran1
	PRINT 'Error occured'
	PRINT ERROR_MESSAGE()

END CATCH




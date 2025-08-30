--!strict
-- PurchaseService.lua
-- Marketplace prompts, authoritative ownership checks, dev product receipts (idempotent)

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")

local GameData = require(script.Parent.GameData)
local Promise = require(script.Parent.Promise)

export type ReceiptInfo = {
	PlayerId: number,
	PurchaseId: string,
	ProductId: number,
	CurrencySpent: number?,
}

local PurchaseService = {}

-- Receipt store for developer products (idempotency)
local Receipts = GameData.ForStore("PurchaseReceipts")

-- In-memory ownership caches (advisory, Marketplace is authority)
local assetCache: { [number]: { [number]: boolean } } = {}
local bundleCache: { [number]: { [number]: boolean } } = {}
local passCache: { [number]: { [number]: boolean } } = {}

local function ensure(map: { [number]: { [number]: boolean } }, userId: number)
	if not map[userId] then
		map[userId] = {}
	end
	return map[userId]
end

--------------------------------------------------------------------
-- Ownership checks (with pcall + cache)
--------------------------------------------------------------------

function PurchaseService.OwnsAsset(player: Player, assetId: number): any
	return Promise.new(function(resolve, reject)
		local m = ensure(assetCache, player.UserId)
		if m[assetId] ~= nil then
			resolve(m[assetId])
			return
		end
		local ok, ownsOrErr = pcall(MarketplaceService.PlayerOwnsAsset, MarketplaceService, player, assetId)
		if not ok then
			reject(ownsOrErr)
			return
		end
		m[assetId] = ownsOrErr == true
		resolve(m[assetId])
	end)
end

function PurchaseService.OwnsBundle(player: Player, bundleId: number): any
	return Promise.new(function(resolve, reject)
		local m = ensure(bundleCache, player.UserId)
		if m[bundleId] ~= nil then
			resolve(m[bundleId])
			return
		end
		local ok, ownsOrErr = pcall(function()
			return MarketplaceService:PlayerOwnsBundle(player, bundleId)
		end)
		if not ok then
			reject(ownsOrErr)
			return
		end
		m[bundleId] = ownsOrErr == true
		resolve(m[bundleId])
	end)
end

function PurchaseService.OwnsGamepass(player: Player, passId: number): any
	return Promise.new(function(resolve, reject)
		local m = ensure(passCache, player.UserId)
		if m[passId] ~= nil then
			resolve(m[passId])
			return
		end
		local ok, ownsOrErr = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId)
		end)
		if not ok then
			reject(ownsOrErr)
			return
		end
		m[passId] = ownsOrErr == true
		resolve(m[passId])
	end)
end

--------------------------------------------------------------------
-- Prompts (UI only; granting is via receipts or ownership re-checks)
--------------------------------------------------------------------

function PurchaseService.PromptAsset(player: Player, assetId: number, equip: boolean?): ()
	MarketplaceService:PromptPurchase(player, assetId, equip == true)
end

function PurchaseService.PromptBundle(player: Player, bundleId: number): ()
	MarketplaceService:PromptBundlePurchase(player, bundleId)
end

function PurchaseService.PromptGamepass(player: Player, passId: number): ()
	MarketplaceService:PromptGamePassPurchase(player, passId)
end

function PurchaseService.PromptDevProduct(player: Player, productId: number): ()
	MarketplaceService:PromptProductPurchase(player, productId)
end

--------------------------------------------------------------------
-- Prompt finished events (update cache after authoritative re-check)
--------------------------------------------------------------------

MarketplaceService.PromptPurchaseFinished:Connect(function(player, assetId, wasPurchased)
	if wasPurchased then
		PurchaseService.OwnsAsset(player, assetId):AndThen(function(owns: boolean)
			if owns then
				ensure(assetCache, player.UserId)[assetId] = true
			end
		end)
	end
end)

MarketplaceService.PromptBundlePurchaseFinished:Connect(function(player, bundleId, wasPurchased)
	if wasPurchased then
		PurchaseService.OwnsBundle(player, bundleId):AndThen(function(owns: boolean)
			if owns then
				ensure(bundleCache, player.UserId)[bundleId] = true
			end
		end)
	end
end)

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, wasPurchased)
	if wasPurchased then
		PurchaseService.OwnsGamepass(player, passId):AndThen(function(owns: boolean)
			if owns then
				ensure(passCache, player.UserId)[passId] = true
			end
		end)
	end
end)

--------------------------------------------------------------------
-- Developer product fulfillment (authoritative, idempotent)
--------------------------------------------------------------------

local productHandlers: { [number]: (receipt: ReceiptInfo, player: Player) -> boolean } = {}

function PurchaseService.SetProductHandler(
	productId: number,
	handler: (receipt: ReceiptInfo, player: Player) -> boolean
): ()
	productHandlers[productId] = handler
end

local function wasProcessed(receiptId: string): any
	return Receipts:Get(receiptId, 0):AndThen(function(v: any)
		return v == true
	end)
end

local function markProcessed(receiptId: string): any
	return Receipts:Set(receiptId, true)
end

MarketplaceService.ProcessReceipt = function(receiptInfo)
	-- Check if already processed
	local processed = false
	wasProcessed(receiptInfo.PurchaseId)
		:AndThen(function(isDone: boolean)
			processed = isDone
		end)
		:OnError(function()
			processed = false
		end)

	if processed then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local handler = productHandlers[receiptInfo.ProductId]
	if not handler then
		warn(("No handler for productId %d"):format(receiptInfo.ProductId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- Grant
	local ok, grantedOrErr = pcall(handler, receiptInfo, player)
	if not ok or grantedOrErr ~= true then
		warn("Product handler failed:", grantedOrErr)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local marked = false
	markProcessed(receiptInfo.PurchaseId)
		:AndThen(function()
			marked = true
		end)
		:OnError(function()
			marked = false
		end)

	if not marked then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	return Enum.ProductPurchaseDecision.PurchaseGranted
end

return PurchaseService

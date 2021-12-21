-- title:  Deckpest
-- author: Jori Kemppi, Jebreel El Shamaly
-- desc:   A Tempest-influenced arcade shooter game with roguelite deckbuilder mechanics.
-- script: lua

-- GLOBAL VALUES AT STARTUP --

timeCurrent = time()
VIEWPORT_LEFT = 16
VIEWPORT_TOP = 16
VIEWPORT_WIDTH = 220
VIEWPORT_HEIGHT = 70

palette = {}
for i = 1, 48 do
	palette[i] = peek(16319 + i)
end

-- GENERAL PURPOSE FUNCTIONS --

function median(list)
	table.sort(list)	
	medianIndex = (#list / 2)
	parity = medianIndex % 1
	if parity == 0 then
		return (list[medianIndex] + list[medianIndex + 1]) / 2	
	else
		return list[medianIndex + 0.5]
	end	
end

function fibonacci(n)
	return n < 2 and n or fibonacci(n - 1) + fibonacci(n - 2)	
end

function accel1D(current, target, velocity, acc, dec, velocityMax, snap)
	delta = target - current
	
	distance = math.abs(delta)	
	velocityAbs = math.abs(velocity)
	
	decelDistance = velocityAbs * velocityAbs / (2 * dec)
	
	if distance > decelDistance then
		velocityAbs = math.min(velocityAbs + acc, velocityMax)
	else
		velocityAbs = math.max(velocityAbs * dec, 0)
	end
	
	if target < current then velocityAbs = -velocityAbs end
	velocity = velocityAbs
	
	current = current + velocity
	
	if distance < snap then
		current = target
		velocity = 0
	end
	
	return current, velocity	
end

function accel2D(current, velocity, target, velocityMax, acc, dec, snap)
	xDelta = target.x - current.x
	yDelta = target.y - current.y
	distance = math.sqrt(xDelta ^ 2 + yDelta ^ 2)
	
	if distance < snap then
	
		x = target.x
		y = target.y
		velocity = 0
		
	else
	
		decelDistance = velocity * velocity / (2 * dec)
		
		if distance > decelDistance then
			velocity = math.min(velocity + acc, velocityMax)
		else
			velocity = math.max(velocity - dec, 0)
		end
		
		angle = math.atan2(yDelta, xDelta)
		x = current.x + velocity * math.cos(angle)
		y = current.y + velocity * math.sin(angle)
		
	end
	
	return Vector.new(x, y), velocity	
end

function getRandomRarity(minimumRarity)
	rarity = minimumRarity or 1

	-- Iterate so that each rarity has a 25% chance to be upgraded to a higher rarity.
	for i = 1, 3 do
		if rarity == i and math.random(4) == 1 then
			rarity = rarity + 1
		end
	end
	
	return rarity	
end

function getRandomCardByRarity(rarity)
	return rarityPool[rarity][math.random(#rarityPool[rarity])]	
end

-- Write a number with sprites
function writeNumber(number, x, y, justify)
	justify = justify or "left"	
	str = tostring(number)
	
	if justify == "right" then
		x = x - 4 * #str + 2
	elseif justify == "center" then
		x = x - 2 * #str + 1
	end
	
	for i = 1, #str do
		n = tonumber(string.sub(str, i, i))
		spr(256 + n, x + (i - 1) * 4, y, 0)
	end	
end

-- An advanced print function with automatic line break and control codes.
function richPrint(message, x, y, width)
	width = width or 239
	c = 12	
	word = ""
	lineWidth = 0
	cursorX = x
	cursorY = y
	realWidth = 0
	
	--Iterate through all the characters.
	i = 1
	while true do
		chr = string.sub(message, i, i)
		
		-- Case: character is a blank space.
		-- Break line if needed, then write the word.
		if chr == " " then
			word_width = print(word, 0, 136)
			if word_width > width - lineWidth then
				cursorX = x
				cursorY = cursorY + 7
				realWidth = math.max(realWidth, lineWidth)
				lineWidth = 0
			end
			print(word, cursorX, cursorY, c)
			cursorX = cursorX + word_width + 4
			lineWidth = lineWidth + word_width + 4
			word = ""
		
		-- Case: character is |
		-- Start parsing a control code.
		elseif chr == "|" then
		
			i = i + 1
			chr = string.sub(message, i, i)
			
			-- Case: control code starts with C
			-- Set color.
			-- syntax: |C[color index]|
			if chr == "C" then
				numstr = ""
				i = i + 1
				while true do
					chr = string.sub(message, i, i)
					if chr == "|" then
						num = tonumber(numstr)
						c = num
						break
					else
						numstr = numstr .. chr
					end
					i = i + 1
				end
			
			-- Case: control code starts with L
			-- Force line break.
			-- Syntax: |L|
			elseif chr == "L" then
				i = i + 1
				realWidth = math.max(realWidth, lineWidth)
				lineWidth = 0
				cursorX = x
				cursorY = cursorY + 7
				
			-- Case: control code starts with S
			-- Draw sprites.
			-- Syntax: |S[sprite id]_[amount of sprites]_[stride]_[sprite width]_[background color]|
			elseif chr == "S" then
				params = {}
				paramI = 1
				numstr = ""
				i = i + 1
				while true do
					chr = string.sub(message, i, i)
					if chr == "_" or chr == "|" then
						num = tonumber(numstr)
						params[paramI] = num
						numstr = ""
						paramI = paramI + 1
					else
						numstr = numstr .. chr
					end
					if chr == "|" then
						spriteX = cursorX + params[2] * params[3]
						for j = 1, params[2] do
							spr(params[1], spriteX - j * params[3], cursorY, params[5])
						end
						cursorX = cursorX + (params[2] - 1) * params[3] + params[4] + 2
						lineWidth = lineWidth + (params[2] - 1) * params[3] + params[4] + 2
						break
					end
					i = i + 1
				end
			end
		
		-- Case: none of the above
		-- Character is a letter, add it to
		-- the word currently being written.
		else		
			word = word .. chr
			-- At the end of the message, add one blank space at the end to trigger the word write condition.
			if i == #message then message = message .. " " end
		
		end
		
		if i == #message then break end		
		i = i + 1
		
	end

	return realWidth, cursorY - y + 5	
end

-- Rasterize a line between two screen space vectors, interpolate the z values, and send each pixel to to the render queue.
function rasterizeLine(v0, z0, v1, z1)
	local l = {}

	-- Set reciprocals for the z values.
	z0Reci = 1 / z0
	z1Reci = 1 / z1
	
	-- Get the difference between v0 and v1.
	vDelta = v1 - v0
	
	-- Get the unit vector to be used as the slope.
	vDeltaUnit = vDelta:clone()
	vDeltaUnit:normalize()
	
	-- Get the slope for the z reciprocal.
	zReciDelta = z1Reci - z0Reci
	zReciSlope = zReciDelta / vDelta:getMag()

	-- Then iterate each pixel unit and send it to the render queue.
	for i = 0, math.ceil(vDelta:getMag()) do
		p = v0 + i * vDeltaUnit
		z_reci = z0Reci + i * zReciSlope
		z = 1 / z_reci
		renderQueue:newObject(z)
		renderQueue:addShape(pix, {p.x, p.y, 12})
	end	
end

-- CLASSLESS OBJECTS --

audio = {
	musicPlaying = false
}

function audio:playMusic()
	if not musicPlaying then
		music(0,-1,-1)
		musicPlaying = true
	end	
end

function audio:stopMusic()
	if musicPlaying then
		music()
		musicPlaying = false
	end	
end

transition = {
	fadingIn = false,
	fadingOut = false,
	target = "",
	phase = 1
}

function transition:update()
	if self.fadingOut then
		self.phase = self.phase - 0.1
		if self.phase <= -1 then
			self.fadingOut = false
			self.fadingIn = true
			return true
		end
		
	elseif self.fadingIn then
		self.phase = self.phase + 0.1
		if self.phase >= 1 then
			self.fadingIn = false
			return true
		end
	end
	
	return false	
end

shop = {
	destroyer = {},
	reminder = {}
}

function shop:init()
	self.selectorRow = 1
	self.selectorColumn = 1
	self.boosterCardsBought = 0	
	self.exit = false
	self.destroyer.active = false
	self.reminder.active = false
	self.booster = Deck:new()
	for i = 1, 5 do
		self.booster:add(cardEmptyShop)
	end
	self.singles = Deck:new()
	self.singles:add(getRandomCardByRarity(getRandomRarity(1)))
	self.singles:add(getRandomCardByRarity(getRandomRarity(1)))
	self.singles:add(getRandomCardByRarity(getRandomRarity(2)))	
	audio:stopMusic()	
end

function shop:input()
	-- Process movement.			
	if self.selectorRow == 1 then
	
		if btnp(2) then
			self.selectorColumn = math.max(1, self.selectorColumn - 1)
		end		
		
		if btnp(3) then
			self.selectorColumn = math.min(9, self.selectorColumn + 1)
		end		
		
		if btnp(1) then
			self.selectorRow = 2
			if self.selectorColumn == 9 then
				self.selectorColumn = 2
			else
				self.selectorColumn = 1
			end
		end	
		
	else	
	
		if btnp(2) and self.selectorColumn == 2 then
			self.selectorColumn = 1
		end		
		
		if btnp(3) and self.selectorColumn == 1 then
			self.selectorColumn = 2
		end	
		
		if btnp(0) then
			self.selectorRow = shop.selectorRow - 1
			if self.selectorRow == 1 then
				if self.selectorColumn == 2 then
					self.selectorColumn = 9
				else
					self.selectorColumn = 1
				end
			end
		end	
		
		if btnp(1) and self.selectorRow == 2 then
			self.selectorRow = 3
		end	
		
	end
	
	-- Process purchases.	
	if btnp(4) then		
	
		if self.selectorRow == 1 then	
		
			-- Try to open new booster.
			if self.selectorColumn == 1 then
				if player:spend(100) then
					self.boosterCardsBought = 0
					-- Get four commons or better, and one uncommon or better.
					for i = 1, 5 do
						if i == 5 then
							rarity = getRandomRarity(2)
						else
							rarity = getRandomRarity()
						end
						self.booster[i] = rarityPool[rarity][math.random(#rarityPool[rarity])]
					end
				end
				table.sort(self.booster, function (a, b) return a.rarity < b.rarity end)
			
			-- Try to get a card from the booster.
			elseif self.selectorColumn >= 2 and self.selectorColumn <= 6 then
				selectedCard = self.booster[self.selectorColumn - 1]
				if selectedCard.isACard then
					if player:spend(self:getBoosterCardPrice()) then
						player.deck:add(selectedCard)
						self.booster[self.selectorColumn - 1] = cardEmptyShop:new()
						self.boosterCardsBought = self.boosterCardsBought + 1
					end
				end
			
			-- Try to get a card from the singles section.
			elseif self.selectorColumn >= 7 and self.selectorColumn <= 9 then
				selectedCard = self.singles[self.selectorColumn - 6]
				if selectedCard.isACard then
					if player:spend(selectedCard:getPrice()) then
						player.deck:add(selectedCard)
						self.singles[self.selectorColumn - 6] = cardEmptyShop:new()
					end
				end
			end
	
		else
	
			-- Try to buy stat upgrades.					
			if self.selectorColumn == 1 then	
			
				if self.selectorRow == 2 then
					if player:spend(self:getHPUpgradePrice()) then
						player.maxHp = player.maxHp + 1
						player:heal(player.maxHp - player.hp)
					end
				end		
				
				if shop.selectorRow == 3 then
					if player:spend(self:getAmmoUpgradePrice()) then
						player.maxAmmo = player.maxAmmo + 1
					end
				end
				
			-- Try to open the card destroyer.
			else	
			
				if player.money >= self.destroyPrice then
					self.destroyer:activate()
				end		
				
			end					
		
		end
		
	end
	
	-- Get the rules reminder text for a card.
	if btnp(7) then
	
		if self.selectorRow == 1 and self.selectorColumn >= 2 and self.selectorColumn <= 6 then		
			selectedCard = self.booster[self.selectorColumn - 1]
			if selectedCard.isACard then
				self.reminder:activate(selectedCard:getReminderText())
			end
			
		elseif self.selectorRow == 1 and self.selectorColumn >= 7 and self.selectorColumn <= 9 then		
			selectedCard = self.singles[self.selectorColumn - 6]
			if selectedCard.isACard then
				self.reminder:activate(selectedCard:getReminderText())
			end
			
		end
		
	end
	
	-- Leave the shop.
	if btnp(5) then
		transition.fadingOut = true
	end	
end

function shop:draw()
	toolTips = {}
		
	rectb(0, 6, 160, 124, 12)
	line(0, 16, 159, 16, 12)
	line(100, 6, 100, 15, 12)
	richPrint("|S272_1_1_3_0|" .. player.money, 103, 9, 100)
	
	line(0, 50, 159, 50, 12)
	line(106, 16, 106, 50, 12)
	spr(1, 7, 22, 1, 1, false, false, 1, 2)
	c = 15
	if self.selectorRow == 1 and self.selectorColumn == 1 then c = 12 end
	rectb(5, 20, 12, 20, c)
	writeNumber(100, 10, 42, "center")
	
	function shopDrawCardSection(numCards, deck, startX, startColumn, sectionId)
		for i = 1, numCards do
			spr(deck[i].spriteId, startX + i * 16, 22, 1, 1, false, false, 1, 2)
			c = 15
			if self.selectorRow == 1 and self.selectorColumn == i + startColumn then c = 12 end
			rectb(startX - 2 + i * 16, 20, 12, 20, c)
			rectb(startX - 1 + i * 16, 21, 10, 18, deck[i]:getRarityAsColor())
			if deck[i].isACard then
				if sectionId == 0 then
					price = self:getBoosterCardPrice()
				else
					price = deck[i]:getPrice()
				end
				writeNumber(price, startX + 3 + i * 16, 42, "center")
			end
		end
	end
	
	shopDrawCardSection(5, self.booster, 12, 1, 0)
	shopDrawCardSection(3, self.singles, 97, 6, 1)
	
	function shopDrawStatBar(y, stat, maxStat, statEmptySprId, statFullSprId, statSprWidth, price, rowNumber)
		c = 14
		if self.selectorRow == rowNumber and self.selectorColumn == 1 then c = 12 end
		if player.money < price then
			if c == 12 then c = 2 else c = 1 end
		end
		rectb(5, y, 134, 10, c)
		for i = 1, maxStat do
			if i > stat then
				sprId = statEmptySprId
			else
				sprId = statFullSprId
			end
			spr(sprId, 7 + (i - 1) * statSprWidth, y + 2, 0)
		end
		writeNumber(price, 136, y + 2, "right")
	end
	
	shopDrawStatBar(54, player.hp, player.maxHp, 275, 273, 8, self:getHPUpgradePrice(), 2)
	shopDrawStatBar(65, player.ammo, player.maxAmmo, 276, 276, 2, self:getAmmoUpgradePrice(), 3)
	
	spr(3, 145, 57, 1, 1, false, false, 1, 2)
	c = 15
	if self.selectorRow > 1 and self.selectorColumn == 2 then c = 12 end
	rectb(143, 55, 12, 20, c)
	
	if self.destroyPrice > 999 then
		writeNumber(self.destroyPrice, 154, 77, "right")
	else
		writeNumber(self.destroyPrice, 148, 77, "center")
	end
	
	line(0, 85, 159, 85, 12)
	
	function shopInfotext(title, info, price)	
		price = price or 0
		width = print(title, 0, 200)
		print(title, 2, 87, 12)
		line(2, 93, 2 + width, 93, 12)
		richPrint(info, 2, 95, 156)
		if price > 0 then
			width = print(price, 0, 200)
			rectb(0, 76, width + 8, 10, 12)
			richPrint("|S272_1_1_3_0|" .. price, 2, 78)
		end		
	end
	
	if self.selectorRow == 1 and self.selectorColumn == 1 then
		shopInfotext("BOOSTER PACK", "Reveal 5 cards (at least one uncommon or better), get up to 2 for free, pay |S272_1_3_3_0|100 for each additional card", 100)
		table.insert(toolTips, {290, "Z", "Buy booster"})
	end
	
	if self.selectorRow == 1 and self.selectorColumn >= 2 and self.selectorColumn <= 6 then	
		selectedCard = self.booster[self.selectorColumn - 1]
		if selectedCard.isACard then
			selectedCard:displayInfotext(0, 85, 160, 45, self:getBoosterCardPrice())
			table.insert(toolTips, {289, "S", "More info"})
			if self:getBoosterCardPrice() == 0 then
				table.insert(toolTips, {290, "Z", "Take card"})
			else
				table.insert(toolTips, {290, "Z", "Buy card"})
			end
		else
			shopInfotext("BOOSTER PACK", "Buy a booster pack to reveal new cards")
		end		
	end
	
	if self.selectorRow == 1 and self.selectorColumn >= 7 and self.selectorColumn <= 9 then	
		selectedCard = self.singles[self.selectorColumn - 6]
		if selectedCard.isACard then
			selectedCard:displayInfotext(0, 85, 160, 45, selectedCard:getPrice())
			table.insert(toolTips, {289, "S", "More info"})
			table.insert(toolTips, {290, "Z", "Buy card"})
		else
			shopInfotext("SINGLE CARDS", "Come back after the next level for more special deals!")
		end		
	end
	
	if self.selectorRow == 2 and self.selectorColumn == 1 then
		shopInfotext("MAX HP", "Maximum health up by |S273_1_7_7_0|1 + full heal", 100 * fibonacci(player.maxHp))
		table.insert(toolTips, {290, "Z", "Buy upgrade"})
	end
	
	if self.selectorRow == 3 and self.selectorColumn == 1 then
		shopInfotext("MAX AMMO", "Increase your maximum ammo by |S276_1_3_3_0|1", 50 * (player.maxAmmo - 9))
		table.insert(toolTips, {290, "Z", "Buy upgrade"})
	end
	
	if self.selectorRow > 1 and self.selectorColumn == 2 then
		shopInfotext("DESTROY", "Remove a card from your deck permanently (the next removal costs double!)")
		table.insert(toolTips, {290, "Z", "Destroy card"})
	end
	
	table.insert(toolTips, {291, "X", "Exit shop"})
	
	y = 117
	for i = #toolTips, 1, -1 do
		spr(toolTips[i][1], 161, y)
		print("/" .. toolTips[i][2] .. ":", 167, y+1, 12)
		print(toolTips[i][3], 161, y + 8, 12)
		y = y - 16
	end	
end

function shop.destroyer:activate()
	self.active = true
	self.confirm_dialog = false
	shop.selector = 1	
end

function shop.destroyer:input()
	if self.confirm_dialog then
		if btnp(4) then
			if player:spend(shop.destroyPrice) then
				table.remove(player.deck, shop.selector)
				shop.destroyPrice = shop.destroyPrice * 2
				shop.selector = 1
				self.active = false
			end
		elseif btnp(5) then
			self.confirm_dialog = false
		end	
	else			
		if btnp(2) then
			shop.selector = math.max(1, shop.selector - 1)
		end		
		if btnp(3) then
			shop.selector = math.min(#player.deck, shop.selector + 1)
		end
		if btnp(4) and player.money >= shop.destroyPrice then
			self.confirm_dialog = true
		end
		if btnp(5) then
			self.active = false
		end		
	end	
end

function shop.destroyer:draw()
	x = 120 + #player.deck * 1.5
	for i = #player.deck, 1, -1 do
		if i == shop.selector then x = x - 11 end
		player.deck[i]:display2D(x, 20)
		if i == shop.selector then
			rectb(x - 1, 19, 12, 20, 12)
			x = x - 11
		end
		x = x - 2
	end	
	
	selectedCard = player.deck[shop.selector]
	selectedCard:displayInfotext(50, 55, 140, 50)
	
	if self.confirm_dialog then
		s = "Destroy " .. selectedCard.name .. "?"
		w = print(s, 0, 136)
		print(s, 120 - w / 2, 110, 12)
		richPrint("|S290_1_5_4_0|/Z: destroy, |S291_1_5_4_0|/X: cancel", 54, 117)
		box_w = math.max(140, w + 6)
		rectb(120 - box_w / 2, 107, box_w, 19, 12)		
	else
		richPrint("|S290_1_5_4_0|/Z: destroy, |S291_1_5_4_0|/X: cancel", 54, 110)
		rectb(50, 107, 140, 12, 12)
	end	
end

function shop.reminder:activate(text)
	self.active = true
	self.text = text	
end

function shop.reminder:input()
	if btnp(5) then
		self.active = false
	end	
end

function shop.reminder:draw()
	w, h = richPrint(self.text, 0, 0, 180)
	cls()
	rectb(28, 68 - h / 2 - 2, 184, h + 5, 12)
	richPrint(self.text, 30, 68 - h / 2, 180)
	richPrint("|S291_1_5_4_0|/X: return to shop", 108, 68 + h / 2 + 4)	
end

function shop:getBoosterCardPrice()
	if shop.boosterCardsBought < 2 then
		return 0
	else
		return 100
	end	
end

function shop:getHPUpgradePrice()
	return 100 * fibonacci(player.maxHp)	
end

function shop:getAmmoUpgradePrice()
	return 50 * (player.maxAmmo - 9)	
end

bullets = {}

function bullets:update()
	-- Sort enemies for hit detection
	table.sort(enemies, function (a, b) return a.z > b.z end)
	
	for i, b in ipairs(self) do
		b:move()
	end
	
	for i = #self, 1, -1 do
		if self[i].expired then
			table.remove(self, i)
		end
	end	
end

function bullets:queueRender()
	for i, b in ipairs(self) do
		b:queueRender()
	end	
end

player = {}

function player:init()
	self.money = 50
	self.hp = 3
	self.maxHp = 3
	self.ammo = 10
	self.maxAmmo = 10
	self.shield = 0
	self.shieldHalflife = 0
	self.damageFlash = 0	
	self.totalMoneyGained = 0
	self.totalMoneySpent = 0
	self.totalHealed = 0
	self.totalDamageDealt = 0
	self.enemiesKilled = 0	
	self.dead = false
	self.cardSelector = 1
	self.lane = 1		
	self.deck = Deck:new()

	for i = 1, 9 do
		self.deck:add(cardAmmo)
	end
	self.deck:add(cardYield)
	
	shop.destroyPrice = 100
end

function player:update()	
	self.damageFlash = math.floor(self.damageFlash * 0.75)
	
	if self.shield > 0 then
		self.shieldHalflife = self.shieldHalflife - timeDelta
		if self.shieldHalflife <= 0 then
			self.shield = math.floor(self.shield / 2)
			self.shieldHalflife = self.shieldHalflife + 1000
		end
	end		
end

function player:spend(amount)
	if self.money >= amount then
		self.money = self.money - amount
		self.totalMoneySpent = self.totalMoneySpent + amount
		return true
	end
	return false	
end

function player:gainMoney(amount)
	player.money = player.money + amount
	player.totalMoneyGained = player.totalMoneyGained + amount	
end

function player:heal(amount)
	self.hp = math.min(self.hp + amount, self.maxHp)
	self.totalHealed = self.totalHealed + amount	
end

function player:reload(amount)
	self.ammo = math.min(self.ammo + amount, self.maxAmmo)	
end

function player:damage(amount, bypassShield)	
	self.damageFlash = 1500
	bypassShield = bypassShield or false
	
	if bypassShield or self.shield == 0 then
		self.hp = self.hp - amount
		
	else
		actualDamage = amount - self.shield
		self.shield = math.max(0, self.shield - amount)
		if actualDamage > 0 then
			self.hp = self.hp - actualDamage
		end
	end
	
	if self.hp <= 0 then
		self.hp = 0
		self.dead = true
	end	
end

function player:gainShield(amount)
	if self.shield == 0 then
		self.shieldHalflife = 1000
	end
	self.shield = self.shield + amount
end

function player:fire()
	if self.ammo > 0 then
		self.ammo = self.ammo - 1
		table.insert(bullets, Bullet:new(self.lane))
	end
end

game = {}
game.level = 1

-- CLASSES --

-- Vector class and methods. Class
-- specifically designed for this
-- game's pseudo-3D needs.
-- Vector format is (x, y, r),
-- because some vectors represent
-- bouding circles and thus have
-- radii, and we want the
-- transformation and projection
-- methods to affect the radius too.
Vector = {}
Vector.__index = Vector

function Vector.new(x, y, r)
	return setmetatable({
		x = x or 0,
		y = y or 0,
		r = r or 0
	}, Vector)
end

-- Replace the x, y and r values of the vector with another.
function Vector:replace(v)
	self.x = v.x
	self.y = v.y
	self.r = v.r
end

-- Clone a vector.
function Vector:clone()
	return Vector.new(self.x, self.y, self.r)
end

-- Get the perpendicular of a vector,
-- rotated counterclockwise.
function Vector:getPerp()
	return Vector.new(self.y, -self.x, self.r)
end

-- Get the magnitude of a vector.
function Vector:getMag()
	return math.sqrt(self.x ^ 2 + self.y ^ 2)
end

-- Set the magnitude of a vector.
function Vector:setMag(mag)
	self:normalize()
	self:replace(self * mag)
end	

-- Normalize a vector.
function Vector:normalize()
	self:replace(self / self:getMag())
end

-- Get the direction of a vector.
function Vector:getDirection()
	return math.atan2(self.y, self.x)
end

-- Rotate a vector in 2D.
-- If theta is not a number, it is
-- assumed to be a table containing
-- a precalculated sine and a cosine
-- (ie. a kind of simplified rotation
-- matrix).
function Vector:rotate(theta)
	local s
	local c
	if type(theta) == "number" then
		s = math.sin(theta)
		c = math.cos(theta)
	else
		s = theta.s
		c = theta.c
	end
	self:replace(Vector.new(c * self.x - s * self.y, s * self.x + c * self.y, self.r))
end

-- Return a clone of the vector,
-- projected to 2D (but not centered
-- in screen space!)
function Vector:project(z)
	return self:clone() * (-120 / z)
end

-- Apply camera transformations to a
-- vector.
function Vector:applyCamera()
	local v = self:clone()
	v = v + cam.current.translate + cam.shake.translate
	v:rotate(cam.current.sinCos)
	v = v * (1 + cam.shake.zoom) * cam.current.zoom
	v = v + Vector.new(VIEWPORT_LEFT + VIEWPORT_WIDTH / 2, VIEWPORT_TOP + VIEWPORT_HEIGHT / 2)
	return v
end

-- Set metamethods.

function Vector.__unm(a)
	local v = Vector.new()
	v.x = -a.x
	v.y = -a.y
	v.r = a.r
	return v
end

function Vector.__add(a, b)
	local v = Vector.new()
	v.x = a.x + b.x
	v.y = a.y + b.y
	v.r = a.r
	return v
end

function Vector.__sub(a, b)
	local v = Vector.new()
	v.x = a.x - b.x
	v.y = a.y - b.y
	v.r = a.r
	return v
end

-- Multiplies a vector by a factor or returns the dot product of two vectors.
function Vector.__mul(a, b)
	if type(a) == "number" then
		return Vector.new(a * b.x, a * b.y, a * b.r)
	elseif type(b) == "number" then
		return Vector.new(b * a.x, b * a.y, b * a.r)
	else
		return a.x * b.x + a.y * b.y
	end
end

function Vector.__div(a, b)
	return Vector.new(a.x / b, a.y / b, a.r / b)
end

-- Get the line equation between two vectors. We need this to rasterize the 3D representation of a card.
lineEquation = {}

function lineEquation:new(v0, v1)
	e = {}
	
	if v0 and v1 then	
	
		-- Case: line is horizontal.
		if v0.y == v1.y then
			e.y = v0.y
			setmetatable(e, lineEquationHorizontal)	
			
		-- Case: line is vertical.
		elseif v0.x == v1.x then
			e.x = v0.x
			setmetatable(e, lineEquationVertical)
		
		-- Case: line is sloping.
		else
			--m = slope, b = intercept
			e.m = (v1.y - v0.y) / (v1.x - v0.x)
			e.b = -v0.x * e.m + v0.y			
			-- Calculate the square root we need for the distance.
			e.sq = math.sqrt(e.m ^ 2 + 1)
			setmetatable(e, lineEquationSlopeIntercept)
			
		end

	else
		setmetatable(e, self)
		e.__index = self
	end
	
	return e	
end

lineEquationHorizontal = lineEquation:new()
lineEquationHorizontal.__index = lineEquationHorizontal

function lineEquationHorizontal:getDistance(v)
	return v.y - self.y	
end

function lineEquationHorizontal:getY(x)
	return self.y	
end

lineEquationVertical = lineEquation:new()
lineEquationVertical.__index = lineEquationVertical

function lineEquationVertical:getDistance(v)
	return v.x - self.x	
end

function lineEquationVertical:getX(y)
	return self.x	
end
	
lineEquationSlopeIntercept = lineEquation:new()
lineEquationSlopeIntercept.__index = lineEquationSlopeIntercept

function lineEquationSlopeIntercept:getDistance(v)
	return (-self.m * v.x + v.y - self.b) / self.sq	
end

function lineEquationSlopeIntercept:getY(x)
	return self.m * x + self.b	
end

function lineEquationSlopeIntercept:getX(y)
	return (y - self.b) / self.m	
end

Lane = {}
Lane.__index = Lane

function Lane.new(p0, p1)
	return setmetatable({
		p0 = p0,
		p1 = p1,
		center = (p0 + p1) / 2,
		last = false
	}, Lane)
end

function Lane:rasterize()
	-- Rasterize left side.
	v1 = self.p0:project(-12):applyCamera()
	v2 = self.p0:project(-4):applyCamera()
	rasterizeLine(v1, -12, v2, -4)
	-- Rasterize back side.
	v1 = self.p0:project(-12):applyCamera()
	v2 = self.p1:project(-12):applyCamera()
	rasterizeLine(v1, -12, v2, -12)
	-- Rasterize front side.
	v1 = self.p0:project(-4):applyCamera()
	v2 = self.p1:project(-4):applyCamera()
	rasterizeLine(v1, -4, v2, -4)
	-- If there are no lanes after this, rasterize right side.
	if self.last then
		v1 = self.p1:project(-12):applyCamera()
		v2 = self.p1:project(-4):applyCamera()
		rasterizeLine(v1, -12, v2, -4)
	end	
end	

Surface = {}
Surface.__index = Surface

-- The constructor takes a table of vectors, representing the intersections of the lanes, generates lane objects for
-- each lane, and returns a table of all the lanes.
function Surface.new(edges)
	local s = {}
	
	for i = 1, #edges - 1 do
		table.insert(s, Lane.new(edges[i], edges[i + 1]))
	end
	
	s[#s].last = true	
	return setmetatable(s, Surface)		
end

function Surface:rasterize()
	for i, l in ipairs(self) do
		l:rasterize()
	end
end

dynamicCamera = {}
dynamicCamera.__index = dynamicCamera

function dynamicCamera.new()
	return setmetatable({
		target = {},
		current = {},
		shake = {},
		targetSet = false,
		currentSet = false,
		hotspots = {}
	}, dynamicCamera)
end

-- Clear the list of hotspots.
function dynamicCamera:initFrame()
	self.hotspots = {}
end

-- Add a hotspot. A hotspot is a vector with a radius, representing a circle that the camera should try to display in full.
function dynamicCamera:addHotspot(p)
	table.insert(self.hotspots, p:clone())	
end

function dynamicCamera:setHotspots()
	local spottedEnemies = false
	
	for i, e in ipairs(enemies) do
		if e:isCritical() then
			self:addHotspot(e:getHotspot())
			spottedEnemies = true
		end
	end
	
	if not spottedEnemies then
		for i, l in ipairs(surface) do
			spot = l.center:project(-12)
			spot.r = 12
			self:addHotspot(spot)
		end
	end
	
	self:addHotspot((surface[player.lane].center + Vector.new(0, 0, 1)):project(-3))	
end

-- Set the target for the camera.
function dynamicCamera:setTarget()
	-- Get a box that contains all the hotspots.	
	spot = self.hotspots[1]
	box = {
		left = spot.x - spot.r,
		right = spot.x + spot.r,
		top = spot.y - spot.r,
		bottom = spot.y + spot.r
	}
	for i = 2, #self.hotspots do
		spot = self.hotspots[i]
		box.left = math.min(box.left, spot.x - spot.r)
		box.right = math.max(box.right, spot.x + spot.r)
		box.top = math.min(box.top, spot.y - spot.r)
		box.bottom = math.max(box.bottom, spot.y + spot.r)
	end		
	
	-- Get the center of the box. The negative of this will be the target translate vector.	
	box.center = {
		x = (box.left + box.right) / 2,
		y = (box.top + box.bottom) / 2
	}

	-- Get the median atan2 of all the hotspots and clamp it to MAX_ROLL. This well be the target roll value of the camera.
	atans = {}	
	for i, spot in ipairs(self.hotspots) do
		if spot.x > 0 then
			a = spot:getDirection()
		else
			a = -spot:getDirection()
		end
		table.insert(atans, a)
	end	
	table.sort(atans)
	medianAtan = median(atans)
	MAX_ROLL = 0.5
	roll = math.max(-MAX_ROLL, math.min(MAX_ROLL, medianAtan))		
	
	-- Get a zoom value that will fit all the hotspots into the viewport. This will be the target zoom value.
	o = self.hotspots[1]
	zoomX = (VIEWPORT_WIDTH / 2) / (math.abs(spot.x) + spot.r)
	zoomY = (VIEWPORT_HEIGHT / 2) / (math.abs(spot.y) + spot.r)
	zoom = math.min(zoomX, zoomY)
	
	for i = 2, #self.hotspots do
		spot = self.hotspots[i]
		zoomX = (VIEWPORT_WIDTH / 2) / (math.abs(spot.x) + spot.r)
		zoomY = (VIEWPORT_HEIGHT / 2) / (math.abs(spot.y) + spot.r)
		zoomThis = math.min(zoomX, zoomY)
		zoom = math.min(zoom, zoomThis)
	end
	
	self.target = {
		translate = Vector.new(-box.center.x, -box.center.y),
		roll = roll,
		zoom = zoom
	}
	
	self.targetSet = true	
end

-- Accelerate the camera's actual values towards the target values.
function dynamicCamera:setCurrent()
	-- If the current values have not been set, set them to be identical with the target.
	if not self.currentSet then
		self.current = {
			translate = self.target.translate:clone(),
			translateV = 0,
			roll = self.target.roll,
			rollV = 0,
			zoom = self.target.zoom,
			zoomV = 0
		}
		self.shake = {
			translate = Vector.new(),
			roll = 0,
			zoom = 0
		}
		self.current.sinCos = {s = 1, c = 0}
		self.currentSet = true
		
	-- Otherwise, accelerate them towards the target.
	
	else	
		-- Set acceleration, deceleration, maximum velocity and snap range for translate, roll and zoom.
		translateAcc = 0.001
		translateDec = 0.001
		translateMaxV = 0.3
		translateSnap = 1
		
		rollAcc = 0.0001
		rollDec = 0.0001
		rollMaxV = 0.002
		rollSnap = 0.005
		
		zoomAcc = 0.0003
		zoomDec = 0.0003
		zoomMaxV = 0.003
		zoomSnap = 0.01
		
		-- Accelerate the values towards the targets. 2D acceleration for the translation, 1D acceleration for roll and zoom.
		self.current.translate, self.current.translateV = accel2D(self.current.translate, self.current.translateV, self.target.translate, translateMaxV, translateAcc, translateDec, translateSnap)		
		self.current.roll, self.current.rollV = accel1D(self.current.roll, self.target.roll, self.current.rollV, rollAcc, rollDec, rollMaxV, rollSnap)
		self.current.zoom, self.current.zoomV = accel1D(self.current.zoom, self.target.zoom, self.current.zoomV, zoomAcc, zoomDec, zoomMaxV, zoomSnap)
		
		-- Set the shake values according to the player's damageFlash value.
		if player.damageFlash > 0 then
			self.shake.translate = Vector.new(player.damageFlash / 20, 0)
			self.shake.translate:rotate(2 * math.pi * math.random())
			self.shake.roll = player.damageFlash * (0.5 - math.random()) / 1000
			self.shake.zoom = player.damageFlash * (0.5 - math.random()) / 1000
		else
			self.shake.translate = Vector.new()
			self.shake.roll = 0
			self.shake.zoom = 0
		end
		
		-- Calculate the trigonometry of the sum of the base roll and shake roll for rotation.
		self.current.sinCos = {s = math.sin(self.current.roll + self.shake.roll), c = math.cos(self.current.roll + self.shake.roll)}
		
	end
	
end

Enemy = {}
Enemy.__index = Enemy

function Enemy.new()
	return setmetatable({}, Enemy)
end

function Enemy:isCritical()
	if self.z > -7 and not self.dying then
		return true
	end	
	return false	
end

function Enemy:queueRender()
	if self.dying then
		renderQueue:newObject(self.z)
		for i, particle in ipairs(self.deathAnim.particles) do
			v = surface[self.lane].center:clone()
			v = v + particle.vector * (1 - 1 / (0.01 * self.deathAnim.time + 1))
			v.r = 1 / (1 + 0.01 * self.deathAnim.time * particle.shrinkSpeed)
			v = v:project(self.z):applyCamera()
			renderQueue:addShape(circ, {v.x, v.y, v.r, 12})
		end

	else
		p = surface[self.lane].center:clone()
		p.r = 0.7		
		pProj = p:project(self.z):applyCamera()
		renderQueue:newObject(self.z)	
		c = 2
		if self.flashTimeout > 0 then
			self.flashTimeout = self.flashTimeout - timeDelta
			c = 12
		end
		renderQueue:addShape(circ, {pProj.x, pProj.y, pProj.r, c})
		renderQueue:addShape(circb, {pProj.x, pProj.y, pProj.r, 12})
		
	end	
end

function Enemy:getHotspot()
	p = surface[self.lane].center:clone()
	p.r = 1
	pProj = p:project(self.z)
	return pProj	
end	

function Enemy:move()
	if not self.dying then
		self.z = self.z + 0.015 * math.random()
		if self.z > -4 then
			self.dead = true
			player:damage(1)
		end
	end	
end

function Enemy:damage(amount)
	player.totalDamageDealt = player.totalDamageDealt + amount
	self.hp = self.hp - amount
	self.flashTimeout = 100
	if self.hp <= 0 then
		self:die()
		player.enemiesKilled = player.enemiesKilled + 1
	end	
end

function Enemy:spawn()
	table.insert(enemies, Enemy.new())
	
	enemies[#enemies].lane = math.random(#surface - 1)
	enemies[#enemies].z = -12
	enemies[#enemies].hp = 3
	enemies[#enemies].dead = false
	enemies[#enemies].dying = false
	enemies[#enemies].flashTimeout = 0
	enemies[#enemies].hittable = true
	
	table.remove(enemyQueue, 1)	
end

function Enemy:die()
	game.enemiesKilledInLevel = game.enemiesKilledInLevel + 1
	player:gainMoney(math.random(2, 5))
	self.hittable = false
	self.dying = true
	self.deathAnim = {}
	self.deathAnim.particles = {}
	for i = 1, 20 do
		local newParticle = {}
		newParticle.vector = Vector.new(1 + 3 * math.random(), 0)
		newParticle.vector:rotate(2 * math.pi * math.random())
		newParticle.moveSpeed = 0.2 + 0.2 * math.random()
		newParticle.shrinkSpeed = 0.2 + 0.2 * math.random()
		table.insert(self.deathAnim.particles, newParticle)
	end
	self.deathAnim.time = 0	
end

function Enemy:updateDeathAnim()
	self.deathAnim.time = self.deathAnim.time + timeDelta
	if self.deathAnim.time > 2000 then
		self.dead = true
	end
end

Bullet = {}

function Bullet:new(l)
	local b = {
		z = -4,
		lane = l,
		expired = false
	}
	setmetatable(b, self)
	self.__index = self
	return b
end

function Bullet:move()
	self.z = self.z - 0.3
	
	for i, e in ipairs(enemies) do
		if e.lane == self.lane and e.hittable and e.z <= self.z and e.z >= self.z - 0.3 then
			e:damage(1)
			self.expired = true
			break
		end
	end
	
	if self.z < -12 then
		self.expired = true
	end	
end

function Bullet:queueRender()
	v = surface[self.lane].center:clone()
	v.r = 0.2
	v = v:project(self.z):applyCamera()
	renderQueue:newObject(self.z)
	renderQueue:addShape(circ, {v.x, v.y, v.r, 12})
end

Card = {}
function Card:new(c)
	c = c or {}
	setmetatable(c, self)
	self.__index = self
	return c
end
Card.isACard = true
Card.hasSupercharge = false

function Card:getRarityAsString()
	rarityStrings = {"common", "uncommon", "rare", "rare AF", "starter", "uncollectable"}
	return rarityStrings[self.rarity]
end

function Card:getRarityAsColor()
	rarityColors = {12, 6, 10, 3, 14, 2}
	return rarityColors[self.rarity]
end

function Card:getPrice()
	rarityPrices = {50, 100, 200, 400}
	return rarityPrices[self.rarity]
end

function Card:getTexel(u, v)
	addr = 0x8000 + 64 * self:getSpriteId() + u // 1
	if v < 8 then
		addr = addr + (v // 1) * 8
	else
		addr = addr + 16 * 64 + ((v // 1) - 8) * 8
	end
	return peek4(addr)
end

function Card:onDraw()
end

function Card:onDiscard()
end

function Card:discard(drawTime)
	table.insert(player.deckDiscard, self)
	self:onDiscard()
	player.hand[self.slot] = cardEmptyHand:new()
	player.hand[self.slot].drawTime = drawTime * 1000
	player.hand[self.slot].drawTime_max = drawTime * 1000
end

function Card:exhaust(drawTime)
	player.hand[self.slot] = cardEmptyShop:new()
	player.hand[self.slot].drawTime = drawTime * 1000
end

function Card:diffuse(minTime, maxTime)
	for i, c in ipairs(player.hand) do
		if i ~= self.slot and c.isACard then
			c:discard(math.random(minTime, maxTime))
		end
	end
end

function Card:adInfinitum(drawTime)
	local otherSlots = {}
	for i, c in ipairs(player.hand) do
		if i ~= self.slot and c.isACard then
			table.insert(otherSlots, i)
		end
	end
	if #otherSlots > 0 then
		player.hand[otherSlots[math.random(#otherSlots)]]:discard(drawTime)
	else
		self:discard(drawTime)
	end
end

function Card:boom(amount)
	local legalTargets = 0
	for i, e in ipairs(enemies) do
		if not e.dying then
			legalTargets = legalTargets + 1
		end
	end
	if legalTargets > 0 then
		divided_amount = amount / legalTargets
		for i, e in ipairs(enemies) do
			if not e.dying then			
				e:damage(divided_amount)
			end
		end
	end
end

function Card:displayInfotext(x, y, width, height, price, showUncollectable)	
	price = price or 0
	showUncollectable = false or showUncollectable
	
	rect(x, y, width, height, 0)
	rectb(x, y, width, height, 12)
	
	timeBoxX = x
	if price > 0 then
		priceBoxWidth = print(price, 0, 136) + 8
		rect(x, y - 9, priceBoxWidth, 10, 0)
		rectb(x, y - 9, priceBoxWidth, 10, 12)
		richPrint("|S272_1_3_3_0|" .. price, x + 2, y - 7, 100)
		timeBoxX = timeBoxX + priceBoxWidth + 2
	end
	
	if self.timeCost > 0 then
		timeBoxWidth = print(self.timeCost, 0, 136) + 10
		rect(timeBoxX, y - 9, timeBoxWidth, 10, 0)
		rectb(timeBoxX, y - 9, timeBoxWidth, 10, 12)
		richPrint("|S278_1_5_5_0|" .. self.timeCost, timeBoxX + 2, y - 7, 100)
	end
	
	print(self.name, x + 2, y + 2, 12)
	line(x, y + 8, x + width - 1, y + 8, 12)
	richPrint(self:getRulesText(), x + 2, y + 10, width - 4)
	
	if showUncollectable or self.rarity < 6 then
		rarityString = self:getRarityAsString()
		rarityStringWidth = print(rarityString, 0, 136)
		print(rarityString, x + width - rarityStringWidth - 1, y + height - 7, self:getRarityAsColor())
	end	
end

function Card:displayReminder(x, y, width, height)
	realWidth, realheight = richPrint(self:getReminderText(), x + 2, y + 200, width - 4)
	rect(120 - realWidth / 2 - 4, y - realheight - 8, realWidth + 8, realheight + 8, 0)
	rectb(120 - realWidth / 2 - 3, y - realheight - 6, realWidth + 6, realheight + 6, 12)
	richPrint(self:getReminderText(), 120 - realWidth / 2, y - realheight - 4, realWidth)
end

function Card:getSpriteId()
	return self.spriteId
end

function Card:display2D(x, y)
	c = self:getRarityAsColor()
	rect(x, y, 10, 18, 0)
	rectb(x, y, 10, 18, c)
	spr(self:getSpriteId(), x + 1, y + 1, -1, 1, false, false, 1, 2)
end

function Card:rulesLinebreak()
	return " |L|"
end

function Card:reminderLinebreak()
	return " |C12||L||L|"
end

function Card:rulesAdInfinitum()
	return "|S280_1_7_7_0|Ad infinitum"
end

function Card:reminderAdInfinitum()
	return self:rulesAdInfinitum() .. " |C14|(If you have other cards in your hand when you play this card, then instead of discarding it, instead discard another card at random for this card's time cost)"
end

function Card:rulesBoom(n)
	return "|S281_1_6_6_0|BOOM " .. n
end

function Card:reminderBoom(n)
	return self:rulesBoom(n) .. " |C14|(Deal " .. n .. " damage divided among all enemies"
end

function Card:rulesDevilsPact()
	return "|S279_1_5_5_0|Devil's pact"
end

function Card:reminderDevilsPact()
	return self:rulesDevilsPact() .. " |C14|(Take 1 damage when you draw this. This damage bypasses your shield.)"
end

function Card:rulesDiffuse(a, b)
	return "|S282_1_6_6_0|Diffuse " .. a .. "-" .. b
end

function Card:reminderDiffuse(a, b)
	return self:rulesDiffuse(a, b) .. " |C14|(When you play this card, also discard every other card in your hand for a random time cost between " .. a .. " and " .. b .. " seconds)"
end

function Card:rulesExhaust()
	return "|S283_1_3_3_0|Exhaust"
end

function Card:reminderExhaust()
	return self:rulesExhaust() .. " |C14|(when you play this card, instead of discarding it, remove it from your deck until the end of the level)"
end

function Card:rulesHeal(n)
	return "|S273_" .. n .. "_6_7_0|Heal " .. n
end

function Card:reminderHeal(n)
	return self:rulesHeal(n) ..  " |C14|(heal " .. n .. " hearts of health)"
end

function Card:rulesReload(n)
	return "|S276_" .. n .. "_2_3_0|Reload " .. n
end

function Card:reminderReload(n)
	return self:rulesReload(n) .. " |C14|(add " .. n .. " ammo)"
end

function Card:rulesShield(n)
	return "|S292_1_4_4_0|Shield " .. n
end

function Card:reminderShield(n)
	return self:rulesShield(n) .. " |C14|(Gain " .. n .. " shield. If you have shield when you take damage, lose that much shield instead. Your shield is halved every second.)"
end

function Card:rulesSupercharge()
	local s = "|S294_1_4_4_0|Supercharge"
	if activeGameMode.name == "action" then s = s .. " (" .. self.superchargeCounters .. ")" end
	return s
end

function Card:reminderSupercharge()
	return self:rulesSupercharge() .. " |C14|(This card enters your hand with 1 supercharge counter. Double the counters whenever you shuffle. When you play this, trigger its effect once for each counter."
end

function Card:rulesYield(a, b)
	return "|S272_1_1_3_0|Yield " .. a .. "-" .. b
end

function Card:reminderYield(a, b)
	return self:rulesYield(a, b) .. " |C14|(gain " .. a .. "-" .. b .. " money at random)"
end

cardAmmo = Card:new()
cardAmmo.timeCost = 1
cardAmmo.name = "Ammo"
cardAmmo.spriteId = 5
function cardAmmo:getReminderText() return self:reminderReload(1) end
function cardAmmo:getRulesText() return self:rulesReload(1) end
function cardAmmo:play()
	player:reload(1)
	self:discard(self.timeCost)
end
cardAmmo.rarity = 5

cardAmmoBelt = Card:new()
cardAmmoBelt.timeCost = 3
cardAmmoBelt.name = "Ammo Belt"
cardAmmoBelt.spriteId = 8
function cardAmmoBelt:getReminderText() return self:reminderAdInfinitum() .. self:reminderLinebreak() .. self:reminderReload(1) end
function cardAmmoBelt:getRulesText() return self:rulesAdInfinitum() .. self:rulesLinebreak() .. self:rulesReload(1) end
function cardAmmoBelt:play()
	player:reload(1)
	self:adInfinitum(self.timeCost)
end
cardAmmoBelt.rarity = 2

cardBlazeCore = Card:new()
cardBlazeCore.timeCost = 5
cardBlazeCore.name = "Blaze Core"
cardBlazeCore.spriteId = 10
function cardBlazeCore:getReminderText() return self:reminderReload(1) .. self:reminderLinebreak() .. "|S293_1_6_6_0|Surplus value: |S281_1_6_6_0|BOOM 1 |C14|(When you discard this for any reason, including playing it, deal 2 damage divided among all enemies)" end
function cardBlazeCore:getRulesText() return self:rulesReload(1) .. self:rulesLinebreak() .. "|S293_1_6_6_0|Surplus value: |S281_1_6_6_0|BOOM 2" end
function cardBlazeCore:play()
	player:reload(1)
	self:discard(self.timeCost)
end
function cardBlazeCore:onDiscard()
	self:boom(2)
end
cardBlazeCore.rarity = 2

cardCosmicStorm = Card:new()
cardCosmicStorm.timeCost = 15
cardCosmicStorm.name = "Cosmic Storm"
cardCosmicStorm.spriteId = 32
function cardCosmicStorm:getReminderText() return self:reminderBoom(2) .. self:reminderLinebreak() .. self:reminderAdInfinitum() end
function cardCosmicStorm:getRulesText() return self:rulesBoom(2) .. self:rulesLinebreak() .. self:rulesAdInfinitum() end
function cardCosmicStorm:play()
	self:boom(2)
	self:adInfinitum(self.timeCost)
end
cardCosmicStorm.rarity = 3

cardDefenseBudget = Card:new()
cardDefenseBudget.timeCost = 15
cardDefenseBudget.name = "Defense Budget"
cardDefenseBudget.spriteId = 15
function cardDefenseBudget:getReminderText() return self:reminderShield(8) .. self:reminderLinebreak() .. "|S293_1_6_6_0|Surplus value: |S272_1_1_3_0|Yield 1-2 |C14|(When you discard this for any reason, including playing it, gain 1-2 money at random)" end
function cardDefenseBudget:getRulesText() return self:rulesShield(8) .. self:rulesLinebreak() .. "|S293_1_6_6_0|Surplus value: " .. self:rulesYield(1, 2) end
function cardDefenseBudget:play()
	player:gainShield(8)
	self:discard(self.timeCost)
end
function cardDefenseBudget:onDiscard()
	player:gainMoney(math.random(1, 2))
end
cardDefenseBudget.rarity = 2

cardDevilsTincture = Card:new()
cardDevilsTincture.timeCost = 15
cardDevilsTincture.name = "The Devil's Tincture"
cardDevilsTincture.spriteId = 4
function cardDevilsTincture:getReminderText() return self:reminderDevilsPact() .. self:reminderLinebreak() .. self:chance() .. "% chance: +1 max HP and full heal (odds go down the more you've healed this game)" end
function cardDevilsTincture:getRulesText() return self:rulesDevilsPact() .. self:rulesLinebreak() .. self:chance() .. "% chance: +1 max HP and full heal (odds go down the more you've healed this game)" end
function cardDevilsTincture:onDraw()
	player:damage(1, true)
end
function cardDevilsTincture:chance()
	local denominator = math.max(1, player.totalHealed * .75)
	return math.ceil(100 / denominator)
end
function cardDevilsTincture:play()
	if math.random(100) <= self:chance() then
		player.maxHp = player.maxHp + 1
		player:heal(player.maxHp - player.hp)
	end
	self:discard(self.timeCost)
end
cardDevilsTincture.rarity = 4

cardFreshClip = Card:new()
cardFreshClip.timeCost = 3
cardFreshClip.name = "Fresh Clip"
cardFreshClip.spriteId = 7
function cardFreshClip:getReminderText() return self:reminderReload(4) end
function cardFreshClip:getRulesText() return self:rulesReload(4) end
function cardFreshClip:play()
	player:reload(4)
	self:discard(self.timeCost)
end
cardFreshClip.rarity = 1

cardGammaRayBurst = Card:new()
cardGammaRayBurst.timeCost = 15
cardGammaRayBurst.name = "Gamma Ray Burst"
cardGammaRayBurst.spriteId = 9
function cardGammaRayBurst:getReminderText() return self:reminderBoom(20) .. self:reminderLinebreak() .. self:reminderDiffuse(3, 5) .. self:reminderLinebreak() .. self:reminderExhaust() end	
function cardGammaRayBurst:getRulesText() return self:rulesBoom(20) .. self:rulesLinebreak() .. self:rulesDiffuse(3, 5) .. self:rulesLinebreak() .. self:rulesExhaust() end
function cardGammaRayBurst:play()
	self:boom(20)
	self:diffuse(3, 5)
	self:exhaust(self.timeCost)
end
cardGammaRayBurst.rarity = 3

cardMeltFurnace = Card:new()
cardMeltFurnace.timeCost = 15
cardMeltFurnace.name = "Melt Furnace"
cardMeltFurnace.spriteId = 13
function cardMeltFurnace:getReminderText() return self:reminderYield(1, 2) .. self:reminderLinebreak() .. self:reminderAdInfinitum() end
function cardMeltFurnace:getRulesText() return self:rulesYield(1, 2) .. self:rulesLinebreak() .. self:rulesAdInfinitum() end
function cardMeltFurnace:play()
	player:gainMoney(math.random(1, 2))
	self:adInfinitum(self.timeCost)
end
cardMeltFurnace.rarity = 3

cardMiningDrone = Card:new()
cardMiningDrone.timeCost = 10
cardMiningDrone.name = "Mining Drone"
cardMiningDrone.spriteId = 14
function cardMiningDrone:getReminderText() return self:reminderYield(2, 5) end
function cardMiningDrone:getRulesText() return self:rulesYield(2, 5) end
function cardMiningDrone:play()
	player:gainMoney(math.random(2, 5))
	self:discard(self.timeCost)
end
cardMiningDrone.rarity = 1

cardStonks = Card:new()
cardStonks.timeCost = 10
cardStonks.name = "Stonks"
cardStonks.spriteId = 11
cardStonks.hasSupercharge = true
function cardStonks:getReminderText() return self:reminderSupercharge() .. self:reminderLinebreak() .. self:reminderYield(2, 3) end
function cardStonks:getRulesText() return self:rulesSupercharge() .. self:rulesLinebreak() .. self:rulesYield(2, 3) end
function cardStonks:onDraw()
	self.superchargeCounters = 1
end
function cardStonks:play()
	for i = 1, self.superchargeCounters do
		player:gainMoney(math.random(2, 3))
	end
	self:discard(self.timeCost)
end
cardStonks.rarity = 3

cardSupplyCrate = Card:new()
cardSupplyCrate.timeCost = 5
cardSupplyCrate.name = "Supply Crate"
cardSupplyCrate.spriteId = 12
function cardSupplyCrate:getReminderText() return self:reminderReload(1) .. self:reminderLinebreak() .. "|S293_1_6_6_0|Surplus value: |S292_1_4_4_0|Shield 4 |C14|(When you discard this for any reason, including playing it, gain 4 shield. If you have shield when you take damage, lose that much shield instead. Your shield is halved every second.)" end
function cardSupplyCrate:getRulesText() return self:rulesReload(1) .. self:rulesLinebreak() .. "|S293_1_6_6_0|Surplus value: |S292_1_4_4_0|Shield 4" end
function cardSupplyCrate:play()
	player:reload(1)
	self:discard(self.timeCost)
end
function cardSupplyCrate:onDiscard()
	player:gainShield(4)
end
cardSupplyCrate.rarity = 1

cardYield = Card:new()
cardYield.timeCost = 15
cardYield.name = "Yield"
cardYield.spriteId = 6
function cardYield:getReminderText() return self:reminderYield(1, 3) end
function cardYield:getRulesText() return self:rulesYield(1, 3) end
function cardYield:play()
	player:gainMoney(math.random(1, 3))
	self:discard(self.timeCost)
end
cardYield.rarity = 5

-- A non-card, representing an empty slot in the shop.
cardEmptyShop = Card:new()
cardEmptyShop.spriteId = 2
cardEmptyShop.rarity = 6
cardEmptyShop.isACard = false
function cardEmptyShop:play()
end

-- A non-card, representing an empty slot in the player's hand.
cardEmptyHand = Card:new()
cardEmptyHand.spriteId = 164
cardEmptyHand.rarity = 6
cardEmptyHand.isACard = false
function cardEmptyHand:play()
end

-- Instead of returning a static sprite id, calculate the sprite id from remaining draw time.
function cardEmptyHand:getSpriteId()
	spr_num = math.floor(11 * self.drawTime / self.drawTime_max + 0.5)
	return 207 - spr_num
end

-- The pool of all collectable cards, separated by rarity.
rarityPool = {}

-- Common cards
rarityPool[1] = {
	cardFreshClip,
	cardMiningDrone,
	cardSupplyCrate
}

-- Uncommon cards
rarityPool[2] = {
	cardAmmoBelt,
	cardBlazeCore,
	cardDefenseBudget
}

-- Rare cards
rarityPool[3] = {
	cardCosmicStorm,
	cardGammaRayBurst,
	cardMeltFurnace,
	cardStonks
}

-- Rare AF cards
rarityPool[4] = {
	cardDevilsTincture
}

-- Deck class. Any collection of cards is a deck object. These collections include the discard pile as well as
-- the booster and singles sections of the shop.

Deck = {}
function Deck:new(d)
	d = d or {}
	setmetatable(d, self)
	self.__index = self
	return d
end

function Deck:sortByRarity()
	table.sort(self, function (a, b) return a.rarity < b.rarity end)
end

function Deck:add(newCard)
	table.insert(self, newCard:new())
end

function Deck:shuffle()
	for i = #self, 2, -1 do
		local j = math.random(i)
		self[i], self[j] = self[j], self[i]
	end
end

function Deck:draw(slot)
	if #self == 0 then
		for i, c in ipairs(player.hand) do
			if c.hasSupercharge then
				c.superchargeCounters = c.superchargeCounters * 2
			end
		end
		while #player.deckDiscard > 0 do
			table.insert(self, table.remove(player.deckDiscard))
		end
		self:shuffle()
	end
	player.hand[slot] = table.remove(self, 1)
	player.hand[slot].slot = slot
	player.hand[slot]:onDraw()
end

RenderQueue = {}
RenderQueue.__index = RenderQueue

function RenderQueue.new()
	return setmetatable({}, RenderQueue)
end

-- Start a new object in the render queue. An object is a collection of shapes that all have the same z coordinate.
function RenderQueue:newObject(z)
	table.insert(self, {shapes = {}, z = z})
end

-- Add a new shape to the most recently created object. A shape is a graphics function and a set of parameters.
function RenderQueue:addShape(func, params)
	table.insert(self[#self], {func = func, params = params})
end

function RenderQueue:render()
	table.sort(self, function (a, b) return a.z < b.z end)
	for i, o in ipairs(self) do
		for j, s in ipairs(o) do
			s.func(table.unpack(s.params))
		end
	end
end

-- The game mode class.
-- A game mode has five methods:
-- init() - initialize the game mode
-- transition() - process the transition to another mode
-- input() - process player input
-- update() - update values
-- draw() - draw the scene

GameMode = {}
function GameMode:new(g)
	g = g or {}
	setmetatable(g, self)
	self.__index = self
	return g
end

-- The action game mode.
gameModeAction = GameMode:new()
gameModeAction.name = "action"

function gameModeAction:init()
	surface = Surface.new({
		Vector.new(-4, 2),
		Vector.new(-3, 2),
		Vector.new(-2, 2),
		Vector.new(-1, 2),
		Vector.new(0, 2),
		Vector.new(1, 2),
		Vector.new(2, 2),
		Vector.new(3, 2),
		Vector.new(4, 2)
	})
	player.deckDraw = Deck:new()
	player.deckDiscard = Deck:new()

	for i, c in ipairs(player.deck) do
		player.deckDraw:add(c)
	end
	player.deckDraw:shuffle()
	
	player.hand = Deck:new()
	for i = 1, 5 do
		player.deckDraw:draw(i)
	end
	
	player.ammo = player.maxAmmo

	enemyQueue = {}
	for i = 1, 16 + game.level * 8 do
		new_enemy = Enemy.new()
		new_enemy.z = -12
		new_enemy.hp = 3
		new_enemy.queueTime = math.random(5000, 120000)
		table.insert(enemyQueue, new_enemy)
	end
	table.sort(enemyQueue, function (a, b) return a.queueTime < b.queueTime end)
	
	game.totalEnemiesInLevel = #enemyQueue
	game.enemiesKilledInLevel = 0

	enemies = {}
	
	-- Clean up bullets, if any exist.
	while #bullets > 0 do
		table.remove(bullets, 1)
	end
	
	cam = dynamicCamera.new()
	audio:playMusic()
end

function gameModeAction:transition()
	if transition.fadingIn then
		transition:update()		
	elseif transition.fadingOut then
		if transition:update() then
			if transition.target == "shop" then
				game.level = game.level + 1
				activeGameMode = gameModeShop:new()				
			elseif transition.target == "gameover" then
				activeGameMode = gameModeGameOver:new()
			end
			activeGameMode:init()
		end
	end	
end

function gameModeAction:input()
	if not transition.fadingOut then
		if btnp(2) then player.lane = math.max(1, player.lane - 1) end
		if btnp(3) then player.lane = math.min(#surface, player.lane + 1) end
		if btnp(6) then player:fire() end	
		if btnp(0) then player.cardSelector = math.max(player.cardSelector - 1, 1) end
		if btnp(1) then player.cardSelector = math.min(player.cardSelector + 1, 5) end	
		if btnp(4) and player.hand[player.cardSelector].isACard then
			player.hand[player.cardSelector]:play()
		end
	end
end

function gameModeAction:update()
	player:update()
	bullets:update()
	
	for i = #enemies, 1, -1 do
		if enemies[i].dead then
			table.remove(enemies, i)
		end
	end
	
	for i, e in ipairs(enemies) do
		if e.dying then
			e:updateDeathAnim()
		else
			e:move()
		end
	end
	
	-- If there are no enemies, make sure the player never has to wait more than 2 seconds for the next spawn.
	if #enemyQueue > 0 then	
		if #enemies == 0 and enemyQueue[1].queueTime > 2000 then
			adjust = enemyQueue[1].queueTime - 2000
		else
			adjust = 0
		end
		for i, e in ipairs(enemyQueue) do
			e.queueTime = e.queueTime - timeDelta - adjust
		end	
		if enemyQueue[1].queueTime <= 0 then
			enemyQueue[1]:spawn()
		end
	end
	
	for i, c in ipairs(player.hand) do
		if c.drawTime then
			c.drawTime = c.drawTime - timeDelta
			if c.drawTime <= 0 then
				player.deckDraw:draw(i)
			end
		end
	end
	
	for i, c in ipairs(player.hand) do
		c:display2D(3, 23 + i * 19)
		if c.drawTime then
			c.drawTime = c.drawTime - timeDelta
		end
	end
	
	if #enemies == 0 and #enemyQueue == 0 then
		transition.fadingOut = true
		transition.target = "shop"
	end
	
	if player.hp <= 0 then
		transition.fadingOut = true
		transition.target = "gameover"
	end
end

function gameModeAction:draw()
	renderQueue = RenderQueue.new()	
	cam:initFrame()
	cam:setHotspots()
	cam:setTarget()
	cam:setCurrent()	
	bullets:queueRender()	
	surface:rasterize()
	
	for i, e in ipairs(enemies) do
		e:queueRender()
	end
	
	-- Rasterize the selected card. Since the card only ever rotates around the z axis, we can take advantage of
	-- the fact that the top and bottom edges are always parallel to optimize the texture mapper.
	
	-- First, rasterize the edges of the card.
	rasterizeLine(surface[player.lane].p0:project(-4):applyCamera(), -4, surface[player.lane].p0:project(-2.2):applyCamera(), -2.2)
	rasterizeLine(surface[player.lane].p1:project(-4):applyCamera(), -4, surface[player.lane].p1:project(-2.2):applyCamera(), -2.2)
	rasterizeLine(surface[player.lane].p0:project(-2.2):applyCamera(), -2.2, surface[player.lane].p1:project(-2.2):applyCamera(), -2.2)
	
	-- Get the vertices of the corners of the card art, plus its bounding box.
	cardArtVerts = {}
	cardArtBox = {}
	function addCardArtVert(p1, p2, dist, z)
		p = p1 + dist * (p2 - p1)
		pProj = p:project(z):applyCamera()
		table.insert(cardArtVerts, pProj:clone())
		cardArtBox = {
			left = math.min(pProj.x, cardArtBox.left or pProj.x),
			right = math.max(pProj.x, cardArtBox.right or pProj.x),
			top = math.min(pProj.y, cardArtBox.top or pProj.y),
			bottom = math.max(pProj.y, cardArtBox.bottom or pProj.y)
		}
	end
	addCardArtVert(surface[player.lane].p0, surface[player.lane].p1, 0.1, -3.9)
	addCardArtVert(surface[player.lane].p0, surface[player.lane].p1, 0.9, -3.9)
	addCardArtVert(surface[player.lane].p0, surface[player.lane].p1, 0.9, -2.3)
	addCardArtVert(surface[player.lane].p0, surface[player.lane].p1, 0.1, -2.3)	
	
	-- Clone the card art vertices.	
	rotatedCardArtVerts = {}
	for i = 1, 4 do
		table.insert(rotatedCardArtVerts, cardArtVerts[i]:clone())
	end
	
	-- Get the direction of the bottom edge.
	bottomDirection = (rotatedCardArtVerts[3] - rotatedCardArtVerts[4]):getDirection()
	
	sinCos = {s = math.sin(-bottomDirection), c = math.cos(-bottomDirection)}	
	-- Rotate the vertices so that the bottom edge is horizontal.
	for i, v in ipairs(rotatedCardArtVerts) do
		v:rotate(sinCos)
	end
	
	-- Get the height of the rotated shape. This is used to calculate the affine v value.
	yDelta = rotatedCardArtVerts[3].y - rotatedCardArtVerts[1].y
	
	-- Get the line equations of the sides. We use them to calculate the affine u value.
	lineEq1 = lineEquation:new(rotatedCardArtVerts[4], rotatedCardArtVerts[1])
	lineEq2 = lineEquation:new(rotatedCardArtVerts[2], rotatedCardArtVerts[3])
	
	-- Get affine UV coordinates for a pixel.
	function getAffineUV(x, y)
	
		-- v = Where the pixel is between the top and the bottom.
		vAffine = (y - rotatedCardArtVerts[1].y) / yDelta
	
		-- Get the points where the sides intersect with a horizontal line at y.
		sideV1 = Vector.new(lineEq1:getX(y), y)
		sideV2 = Vector.new(lineEq2:getX(y), y)
	
		-- u = Where the pixel is between the intersection points.		
		xDelta = sideV2.x - sideV1.x
		uAffine = (x - sideV1.x) / xDelta
		
		return uAffine, vAffine
		
	end
	
	-- Iterate through every pixel in the card art bounding box, rotate it according to the direction of the bottom edge
	-- and get its affine UV coordinates.
	
	for x = cardArtBox.left, cardArtBox.right do
		for y = cardArtBox.top, cardArtBox.bottom do
		
			p = Vector.new(x, y)
			p:rotate(sinCos)
			uAffine, vAffine = getAffineUV(p.x, p.y)

			-- If the affine UV coordinates are within range, perform perspective correction and send to the render queue.
			if uAffine >= 0 and uAffine <= 1 and vAffine >= 0 and vAffine <= 1 then
				uCorrect = math.max(0, math.min(8, uAffine * 8))
				zReci = 1 / -3.9 + vAffine * ((1 / -2.3) - (1 / -3.9))
				zCorrect = 1 / zReci
				vReci = vAffine * (16 / -2.3)
				vCorrect = math.max(0, math.min(16, vReci * zCorrect))				
				renderQueue:newObject(zCorrect)
				renderQueue:addShape(pix, {x, y, player.hand[player.cardSelector]:getTexel(uCorrect, vCorrect)})
				
			end
		end
	end
	
	renderQueue:render()

	selectedCard = player.hand[player.cardSelector]
	if selectedCard.isACard then
		selectedCard:displayInfotext(14, 89, 223, 47)
	end
		
	y = 23 + player.cardSelector * 19
	line(0, y, 0, y + 17, 12)
	pix(1, y, 12)
	pix(1, y + 17, 12)	
	
	for i = 1, player.maxHp do
		if i > player.hp then
			sprId = 275
		else
			sprId = 273
		end
		spr(sprId, (i - 1) * 8, 0, 0)
	end

	for i = 1, player.shield do
		spr(292, player.maxHp * 8 + (i - 1) * 2, 0, 0)
	end
	
	for i = 1, player.maxAmmo do
		if i > player.ammo then
			sprId = 277
		else
			sprId = 276
		end
		spr(sprId, (i - 1) * 2, 7, 0)
	end
	
	richPrint("|S272_1_1_3_0|" .. player.money, 0, 15)
	
	levelString = "Level " .. game.level
	w = print(levelString, 0, 140)
	print(levelString, 240 - w, 1, 12)
	
	rect(185, 7, 54, 4, 0)
	rectb(185, 7, 54, 4, 12)
	
	progressBarWidth = 52 * game.enemiesKilledInLevel / game.totalEnemiesInLevel
	if progressBarWidth > 0 then
		rect(186, 8, progressBarWidth, 2, 5)
	end
	
	progressString = game.enemiesKilledInLevel .. "/" .. game.totalEnemiesInLevel
	w = print(progressString, 0, 140)
	print(progressString, 240 - w, 12, 12)	
end

gameModeShop = GameMode:new()
gameModeShop.name = "shop"

function gameModeShop:init()
	shop:init()	
end

function gameModeShop:transition()
	if transition.fadingIn then
		transition:update()			
	elseif transition.fadingOut then
		if transition:update() then
			activeGameMode = gameModeAction:new()
			activeGameMode:init()
		end	
	end	
end

function gameModeShop:update()
end

function gameModeShop:input()
	if not transition.fadingIn and not transition.fadingOut then	
		if shop.destroyer.active then
			shop.destroyer:input()			
		elseif shop.reminder.active then
			shop.reminder:input()			
		else		
			shop:input()			
		end			
	end	
end

function gameModeShop:draw()
	if shop.destroyer.active then
		shop.destroyer:draw()		
	elseif shop.reminder.active then
		shop.reminder:draw()		
	else	
		shop:draw()
	end	
end

gameModeGameOver = GameMode:new()
gameModeGameOver.name = "gameover"

function gameModeGameOver:init()
	self.exit = false
	self.summary = {
		"Level reached: " .. game.level,
		"Money gained: " .. player.totalMoneyGained,
		"Money spent: " .. player.totalMoneySpent,
		"Damage healed: " .. player.totalHealed,
		"Damage dealt to enemies: " .. math.floor(player.totalDamageDealt + 0.5),
		"Enemies killed: " .. player.enemiesKilled
	}	
	audio:stopMusic()	
end

function gameModeGameOver:transition()
	if transition.fadingIn then
		transition:update()		
	elseif transition.fadingOut then
		if transition:update() then
			activeGameMode = gameModeNewGame:new()
			activeGameMode:init()
		end
		
	end	
end

function gameModeGameOver:input()
	if btnp(4) then
		transition.fadingOut = true
	end	
end

function gameModeGameOver:update()
end

function gameModeGameOver:draw()
	print("GAME OVER", 0, 0, 12, false, 3)
	y = 21
	for i, l in ipairs(self.summary) do
		print(l, 0, y, 12)
		y = y + 7
	end	
	y = y + 7
	richPrint("|S290_1_5_4_0|/Z: try again", 0, y)	
end

gameModeNewGame = GameMode:new()
gameModeNewGame.name = "newgame"

function gameModeNewGame:init()
	player:init()
	game.level = 1	
end

function gameModeNewGame:transition()
	if transition.fadingIn then
		transition:update()		
	elseif transition.fadingOut then
		if transition:update() then
			activeGameMode = gameModeAction:new()
			activeGameMode:init()
		end		
	end	
end

function gameModeNewGame:input()
	if btnp(4) then
		transition.fadingOut = true
	end	
end

function gameModeNewGame:update()
end

function gameModeNewGame:draw()
	function printCenter(message, y, scale)
		scale = scale or 1
		local w = print(message, 0, 200, 0, false, scale)
		print(message, 120 - w / 2, y, 12, false, scale)
	end	
	map(0, 0, 25, 4, 20, 3)

	richPrint("left/right: choose lane", 58, 38)
	richPrint("|S288_1_5_4_0|/A: fire cannon", 78, 45)	
	richPrint("up/down: choose card", 63, 55)
	richPrint("|S290_1_5_4_0|/Z: play card", 82, 62)	
	printCenter("all cards have a time cost", 72)
	printCenter("played and discarded cards", 79)
	printCenter("will be replaced after", 86)
	printCenter("that time has passed", 93)	
	richPrint("|S290_1_5_4_0|/Z: start game", 79, 120)		
end

activeGameMode = gameModeNewGame:new()
activeGameMode:init()

function TIC()
	timePrevious = timeCurrent
	timeCurrent = time()
	timeDelta = timeCurrent - timePrevious

	cls()
	
	activeGameMode:transition()
	activeGameMode:input()
	activeGameMode:update()
	activeGameMode:draw()	
end

function SCN(y)
	if activeGameMode.name == "action" and player.damageFlash > 0 then
		scanlineFlash = math.random(player.damageFlash)
	else
		scanlineFlash = 0
	end

	brightness = math.max(0, math.min(1, transition.phase + (y % 8) / 8))
	
	for i = 1, 48 do
		val = brightness * palette[i] + (1 - brightness) * palette[(i - 1) % 3 + 1]
		if activeGameMode.name == "action" then
			if player.damageFlash > 500 then
				val = 255 - val
			end
			if i % 3 == 1 then
				val = math.min(255, val + scanlineFlash)
			end

		end
		poke(16319 + i, val)
	end	
end

-- <TILES>
-- 001:1222222122222222224443222244442222224422222244222234442222444322
-- 002:0000000000000000000000000000000000000000022002200222222000222200
-- 003:0000000000000000012222100222222001111110022222200222222002122120
-- 004:0000000002000020022222200212212002222220022112200122221000000000
-- 005:00000000000cc00000cddc000cddddc00cddddc00cddddc00cddddc00cddddc0
-- 006:00000000000000000014100000444f0002444200034443000444441004444410
-- 007:00000000000000000ccccc000cdddcc00ccccc000ccccc000cdddcc00ccccc00
-- 008:0000000000dedd0000ffff0000dedd0000ffff0000dedd0000ffff0000dedd00
-- 009:00000000009bb900009bb900009bb9000a9bb9a000abba000eabbae0edccccde
-- 010:000200000204000000040020002420000114110f0ef44fe0eef34feeeff44ffe
-- 011:0000000001334410033444400334848003344440033434400334433001344440
-- 012:0000000000000000000000000877778007777770087777800766667006666660
-- 013:000000000feeeef00eeffee0ee2442eeef4444feef4444feee2442ee0eee4ee0
-- 014:0000000002322320044444400033330001444410034444300304403003000030
-- 015:00000000000000000b8008b00bbbbbb00b9999b00b9119b00b9449b00b9449b0
-- 017:2244222222442222224422222222222222442222224422222222222212222221
-- 018:0022220002222220022002200000000000000000000000000000000000000000
-- 019:0212212002122120021221200222222002222220012222100000000000000000
-- 020:0000000000055000000550000555555005555550000550000005500000000000
-- 021:0cddddc00ceeeec00ceeeec00cddddc00cddddc00cddddc00cccccc000000000
-- 022:0444441004444410034443000244420000444100001410000000000000000000
-- 023:0ccccc000cdddcc00ccccc000ccccc000cdddcc00ccccc000000000000000000
-- 024:00ffff0000dedd0000ffff0000dedd0000ffff0000dedd000000000000000000
-- 025:fddccddf0eeddee0009ee900009bb900009bb900009bb900009bb90000000000
-- 026:eef43ffeeff44fee0ef34fe000114110000242000200400000e0202000000000
-- 027:0fc344f0fffc3cfffffcacffffffafffffffafffffffffffffffffffffffffff
-- 028:0655556006555560066666600766667000000000000000000000000000000000
-- 029:0f0240f00f0420f00f0410f00f0400f00e3433e00e4444e00eeeeee000000000
-- 030:023cc320009bb900009bb900909bb9898b9bb9bee8bbbb8fef8888eeeeeeefee
-- 031:0b9119b00b9999b00ba99ab009b99b9008baab80009bb9000000000000000000
-- 032:00080000008b088000ab89a808bbaa8008bca80088bcbb808bc0cab88bc0caa8
-- 048:0bc0cb9a0bc0cb8aabbcb88a08bbb889008ab880008aa8000008a8000008a800
-- 196:0000000000000000000000000000000000000000022002200222222000222200
-- 197:0000000001000010000000000000000000000000022002200222222000222200
-- 198:0000000002100120010000100000000000000000012002100222222000222200
-- 199:0000000003211230021001200100001000000000001001000122221000222200
-- 200:0000000003322330032112300210012001000010000000000012210000222200
-- 201:0000000003333330033223300321123002100120010000100001100000122100
-- 202:0000000003333330033333300332233003211230021001200100001000011000
-- 203:0000000003333330033333300333333003322330032112300210012001000010
-- 204:0000000003333330033333300333333003333330033223300321123002100120
-- 205:0000000003333330033333300333333003333330033333300332233003211230
-- 206:0000000003333330033333300333333003333330033333300333333003322330
-- 207:0000000003333330033333300333333003333330033333300333333003333330
-- 212:0022220002222220022002200000000000000000000000000000000000000000
-- 213:0022220002222220022002200000000000000000000000000100001000000000
-- 214:0022220002222220012002100000000000000000010000100210012000000000
-- 215:0022220001222210001001000000000001000010021001200321123000000000
-- 216:0022220000122100000000000100001002100120032112300332233000000000
-- 217:0012210000011000010000100210012003211230033223300333333000000000
-- 218:0001100001000010021001200321123003322330033333300333333000000000
-- 219:0100001002100120032112300332233003333330033333300333333000000000
-- 220:0210012003211230033223300333333003333330033333300333333000000000
-- 221:0321123003322330033333300333333003333330033333300333333000000000
-- 222:0332233003333330033333300333333003333330033333300333333000000000
-- 223:0333333003333330033333300333333003333330033333300333333000000000
-- 231:00000000ccccccccaaaaaaaaaaaaaaaaaaaaaaaa99aaaa99ccaaaacc0caaaac0
-- 232:0caaaac0caaaaac0aaaaaac0aaaaaac0aaaaa9c099999c00ccccc00000000000
-- 233:0000000000cccccc0c9aaaaa00c9aaaa000c9aaa0000c99900000ccc00000000
-- 234:00000000c0000000ac000000aac00000aaac00009999c000cccc000000000000
-- 235:00000000cccc0000aaa9c000aa9c0000a9c000009c000000c000000000000000
-- 236:0caaaac00caaaacc0caaaaaa0caaaaaa0caaaaaa0caaaa990caaaacc0caaaac0
-- 237:caaaa9c0aaaa9c00aaa9c000aaac0000aaac0000aaaac0009aaaac00c9aaaac0
-- 238:0c9aaaac00c9aaaa000c9aaa0000c9aa00000c9a000000c90000000c00000000
-- 239:00000000c0000000ac000000aac00000aaac0000aaaac0009aaaac00c9aaaac0
-- 240:0caaaac00caaaac00caaa9c00caa9c000ca9c0000c9c000000c0000000000000
-- 241:0caaaac00caaaac00c9aaac000c9aac0000c9ac00000c9c000000c0000000000
-- 242:0000000000000c000000cac0000caac000caaac00caaaac00caaaac00caaaac0
-- 243:0caaaac00caaaac00caaaac00caaaac00caaaac00caaaac00caaaac00caaaac0
-- 244:00000000000ccccc00caaaaa0caaaaaa0caaaaaa0caaaaa90caaaa9c0caaaac0
-- 245:00000000ccc00000aaac0000aaaac000aaaaac00999999c0cccccc0000000000
-- 246:00000000cccccc00aaaaa9c0aaaa9c00aaa9c000999c0000ccc0000000000000
-- 247:00000000c0000000ac000000ac000000ac0000009c000000c000000000000000
-- 248:000000000000000c000000ca000000ca000000ca000000c90000000c00000000
-- 249:0caaaac00caaaaac0caaaaaa0caaaaaa0c9aaaaa00c99999000ccccc00000000
-- 250:00000000ccccc000aaaaac00aaaaaac0aaaaaac09aaaaac0c9aaaac00caaaac0
-- 251:000000000000000c000000ca00000caa0000caaa000caaaa00caaaa90caaaa9c
-- 252:caaaa9c0aaaa9c00aaa9c000aa9c0000a9c000009c000000c000000000000000
-- 253:0000000000c000000cac00000caac0000caaac000caaaac00caaaac00caaaac0
-- 254:00000000ccccccccaaaaaaaaaaaaaaaaaaaaaaaa99999999cccccccc00000000
-- 255:0000000000000ccc0000caaa000caaaa00caaaaa0c99999900cccccc00000000
-- </TILES>

-- <SPRITES>
-- 000:0c000000c0c00000c0c00000c0c000000c000000000000000000000000000000
-- 001:0c000000cc0000000c0000000c0000000c000000000000000000000000000000
-- 002:cc00000000c000000c000000c0000000ccc00000000000000000000000000000
-- 003:ccc0000000c000000c00000000c00000cc000000000000000000000000000000
-- 004:c0c00000c0c00000ccc0000000c0000000c00000000000000000000000000000
-- 005:ccc00000c0000000cc00000000c00000cc000000000000000000000000000000
-- 006:0cc00000c0000000ccc00000c0c000000cc00000000000000000000000000000
-- 007:ccc0000000c000000c000000c0000000c0000000000000000000000000000000
-- 008:0c000000c0c000000c000000c0c000000c000000000000000000000000000000
-- 009:cc000000c0c00000ccc0000000c00000cc000000000000000000000000000000
-- 016:1410000044400000444000004440000044400000141000000000000000000000
-- 017:0cc0cc00c22c22c0c22222c00c222c0000c2c000000c00000000000000000000
-- 018:0cc0cc00c00c00c0c00000c00c222c0000c2c000000c00000000000000000000
-- 019:0cc0cc00c00c00c0c00000c00c000c0000c0c000000c00000000000000000000
-- 020:0c000000cdc00000cdc00000cdc00000cdc00000ccc000000000000000000000
-- 021:0c000000c0c00000c0c00000c0c00000c0c00000ccc000000000000000000000
-- 022:ccccc000cfdfc0000cdc00000cdc0000cedec000ccccc0000000000000000000
-- 023:2000200022222000212120002222200022222000022200000000000000000000
-- 024:000000000aa0aa00a00a00a0a00a00a00aa0aa00000000000000000000000000
-- 025:2022020002332000234432002344320002332000202202000000000000000000
-- 026:2002002002020200002320000023200002020200200200200000000000000000
-- 027:efe00000f0f00000e0e00000e0e00000f0f00000efe000000000000000000000
-- 032:0aaa0000a8a8a000aa8aa000a8a8a000a8a8a0000aaa00000000000000000000
-- 033:0444000041414000414140004414400044144000044400000000000000000000
-- 034:0555000055655000565650005666500056565000055500000000000000000000
-- 035:0222000021122000211220002121200021122000022200000000000000000000
-- 036:bbbb0000b99b0000b99b0000b99b0000b99b00000bb000000000000000000000
-- 037:0efff0000efff0000efff0000efff00002222000efffff000000000000000000
-- 038:08b0000009b00000ab00000000ba00000b9000000b8000000000000000000000
-- </SPRITES>

-- <MAP>
-- 001:ffefefaf8fef6f4fef6f2fbfbe2f9efe9eef6f4fefae9e7e6f0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 002:00dfbfcfffef7f3f0000cede00ceefcf8fef7f9fefaf003f000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 003:009fcfffefef5f9fef5f1feeae1f0000ffefae9eef8e000f000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- </MAP>

-- <WAVES>
-- 000:00000000ffffffff00000000ffffffff
-- 001:0123456789abcdeffedcba9876543210
-- 002:0123456789abcdef0123456789abcdef
-- </WAVES>

-- <SFX>
-- 000:06000600060006000600060006000600060006000600060006000600f600f600f600f600f600f600f600f600f600f600f600f600f600f600f600f600304000000000
-- 001:0010002e0030005b0070008900a800b000c000d000d000b00080f070f059f03af03df03ff021f022f023f024f024f024f052f071f0b0f0c0f0c0f000000000000000
-- 002:0000000000000000000000000000000000000000000000000000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000f000000000000000
-- </SFX>

-- <PATTERNS>
-- 000:700024000000100020100020600016100020100000000000600006000000100020000000100020000000700024100020100020100020700026100020700024100020100020000000600002000000100020000000100030000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 001:400022100020500022600022400022100020500022100020800022100020900022a00022900022100020700022100020500022100020500022600022400022500022500022600022f00022c00022900022600022400022000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- </PATTERNS>

-- <TRACKS>
-- 000:180000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000200
-- 001:1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005e0200
-- 002:180000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000200
-- </TRACKS>

-- <SCREEN>
-- 000:000000000000000000000000000000000000000000ff0000e0000000e0000000000000fe000000000000000f0f0000000000000f0000000000000e0e00e0000000000000f0e0000000000000000f000e0000f000e00ff0000000000eff0e0000000ff0000000000000000ee00000000000000000ee000000
-- 001:00000000000000000000000000000000000000000000f0000e0000000e0000000000000fe000000000000000ff0000000000000f0000000000000e0e00e0000000000000f0e0000000000000000f00e0000f000e00fff000000000effee000000ff0000000000000000ee00000000000000000ee0000000e
-- 002:ee0000000000000000000000000000000000000000000ff000ee000000e000000000000f0e00000000000000f0f000000000000f0000000000000e0e00e000000000000f0ee000000000000000f00e00000f00e00fff000000000e0fe0000000ff0000000000000000e00000000000000000ee0000000ee0
-- 003:00ee0000000000000000000000000000000000000000000f0000e000000e000000000000f0e00000000000000f0f00000000000f0000000000000e0e00e000000000000f0e0000000000000000f00e0000f00e00fff00000000ee0fe0000000ff000000000000000ee0000000000000000ee0000000ee000
-- 004:0000ee000000000000000000000000000000000000000000f0000e000000ee00000000000fe00000000000000f0f000000000000f000000000000e0e00e000000000000f0e000000000000000f00e0000f00e00fff00000000efffe000000ff0000000000000000e0000000000000000ee0000000ee00000
-- 005:000000ee00000000000000000000000000000000000000000ff000e0000000e00000000000fe00000000000000f0f00000000000f000000000000e0e0e000000000000f0ee00000000000000f00e0000f000e0fff00000000eff0e000000ff000000000000000ee000000000000000ee0000000ee0000000
-- 006:00000000ee00000000000000000000000000000000000000000f000ee000000e00000000000fe0000000000000f0f00000000000f000000000000e0e0e000000000000f0ee00000000000000f0ee0000f00e0fff00000000eff0e000000ff00000000000000ee000000000000000ee0000000ee000000000
-- 007:0000000000ee0000000000000000000000000000000000000000f0000e000000e00000000000fe0000000000000f0f00000000000f00000000000e0e0e000000000000f0e00000000000000f00e0000f00e0fff00000000effee00000fff00000000000000e000000000000000ee000000eee00000000000
-- 008:e00000000000eee00000000000000000000000000000000000000ff000e000000e00000000000fe0000000000000ff00000000000f00000000000e0e0e000000000000fee0000000000000f00e0000f00e0fff00000000effe000000ff00000000000000ee00000000000000ee000000ee00000000000000
-- 009:0ee000000000000ee00000000000000000000000000000000000000f000e000000e0000000000f0e000000000000f0f0000000000f00000000000e0e0e00000000000f0ee0000000000000f0ee000f00e00ff00000000e0fe000000ff0000000000000ee00000000000000ee000000ee0000000000000000
-- 010:000eee00000000000ee0000000000000000000000000000000000000f000ee00000e0000000000fe0000000000000ff0000000000f00000000000e0e0e00000000000f0e0000000000000f00e000f00e00ff00000000e0fe00000fff0000000000000e00000000000000ee000000ee000000000000000000
-- 011:000000ee00000000000ee000000000000000000000000000000000000ff000e00000e0000000000fe000000000000f0f0000000000f0000000000eee0e000000000000ee000000000000f00e0000f00e0ff00000000effe00000ff0000000000000ee0000000000000ee000000ee00000000000000000000
-- 012:00000000eee0000000000ee000000000000000000000000000000000000f000e00000e0000000000fe000000000000ff0000000000f0000000000eee0e000000000000ee000000000000f0ee000f00e0ff00000000ef0e00000ff000000000000ee0000000000000ee000000ee0000000000000000000000
-- 013:00000000000ee0000000000ee00000000000000000000000000000000000f000e00000e0000000000fe00000000000f0f000000000f00000000000ee0e000000000000e000000000000f00e000f00e0ff0000000eefee0000fff000000000000e0000000000000ee000000ee000000000000000000000000
-- 014:0000000000000ee0000000000eee000000000000000000000000000000000ff00ee0000ee000000000fe00000000000ff0000000000f0000000000ee0e00000000000ee000000000000f0e000f00e0fff000000effe00000ff000000000000ee000000000000ee000000ee00000000000000000000000000
-- 015:000000000000000eee0000000000ee000000000000000000000000000000000f000e00000e000000000fe00000000000ff000000000f0000000000ee0e00000000000ee00000000000f0ee000f0e0fff000000effe00000ff000000000000e000000000000ee00000eee0000000000000000000000000000
-- 016:000000000000000000ee0000000000ee00000000000000000000000000000000f000e00000e00000000f0e0000000000ff000000000f0000000000e00e00000000000e00000000000f00e000f0e0fff000000effe00000ff00000000000ee00000000000ee00000ee0000000000000000000000000000000
-- 017:00000000000000000000eee000000000ee0000000000000000000000000000000ff00e00000e00000000fe00000000000ff00000000f0000000000e0000000000000ee00000000000f0e000f00efff000000effe0000ff00000000000ee00000000000ee00000ee000000000000000000000000000000000
-- 018:eff00000000000000000000ee000000000ee0000000000000000000000000000000f00ee0000e00000000fe0000000000f0000000000f000000000e0000000000000ee0000000000f0e000f00efff000000ef0e0000ff00000000000e00000000000ee00000ee00000000000000000000000000000000000
-- 019:0eeeff0000000000000000000eee00000000ee000000000000000000000000000000f000e0000e00000000fe0000000000f000000000f000000000e0000000000000e0000000000f00e000f0e0ff000000efee0000ff0000000000ee00000000000e00000ee000000000000000000000000000000000000e
-- 020:ee00eeeff0000000000000000000ee00000000eee0000000000000000000000000000ff00e0000e00000000fe000000000f0000000000000000000e000000000000ee0000000000f0e000f0e0ff000000efe0000ff0000000000ee00000000000ee0000ee00000000000000000000000000000000000eee0
-- 021:00eee00eeeff000000000000000000ee000000000ee0000000000000000000000000000f00e0000e00000000fe000000000f000000000000000000e000000000000ee000000000f0e000f0e0ff000000efe0000ff0000000000e00000000000ee0000ee0000000000000000000000000000000000eee0000
-- 022:00000eee00eeeff00000000000000000eee00000000ee000000000000000000000000000f00ee000e00000000fe000000000f00000000000000000e000000000000e0000000000fee0000e0ff000000efe0000ff000000000ee0000000000ee0000ee000000000000000000000000000000000eee0000000
-- 023:ff000000eeee0eeeff00000000000000000ee00000000ee00000000000000000000000000ff00e000e0000000f0e00000000f00000000000000000e000000000000e000000000f0e00000eff000000ffe000ff000000000ee0000000000ee000eee00000000000000000000000000000000eee0000000000
-- 024:00ffff000000eee0eeeff0000000000000000eee0000000ee00000000000000000000000000f00e000ee000000fe000000000f00000000000000000000000000000000000000f0e00000eff00000ef0e000ff000000000e0000000000ee000ee00000000000000000000000000000000eee0000000000000
-- 025:000000fff000000eee0eeeff0000000000000000ee0000000eee000000000000000000000000f00e0000e000000fe00000000f00000000000000000000000000000000000000fee0000eff00000efee000ff00000000ee000000000ee000ee000000000000000000000000000000eeee000000000000000e
-- 026:000000000ffff00000eee0eeeff000000000000000eee0000000ee00000000000000000000000ff0ee000e000000fe00000000f000000000000000000000000000000000000f0e0000eff00000efe000ff000000000e000000000ee000ee00000000000000000000000000000eee000000000000000eeee0
-- 027:0000000000000fff00000eee0eeeff000000000000000ee0000000ee00000000000000000000000f00e000e0000000e0000000f0000000000000000000000000000000000000e0000ef0f0000efe000ff00000000ee00000000ee000ee0000000000000000000000000000eee000000000000000eee00000
-- 028:0000000000000000fff00000eeeeeeeff00000000000000eee000000ee0000000000000000000000f00e000e0000000e0000000f0000000000000000000000000000000000000000ef0f0000efe000ff0000000ee00000000ee000ee000000000000000000000000000eee00000000000000eeee00000000
-- 029:0000000000000000000ffff00000eeeeeeff00000000000000ee000000ee000000000000000000000ff00000e0000000e00000000000000000000000000000000000000000000000eff0000ef0000f00000000e00000000ee000ee00000000000000000000000000eee0000000000000eeee000000000000
-- 030:00000000000000000000000fff00000eeeeeeff0000000000000ee000000ee000000000000000000000f000000000000e0000000000000000000000000000000000000000000000eff0000ff0000f0000000ee0000000ee000ee0000000000000000000000000eee000000000000eeee0000000000000000
-- 031:00000000000000000000000000ffff0000eeeeeeff000000000000eee00000eee0000000000000000000f000000000000e00000000000000000000000000000000000000000000eff0000f0000ff000000ee0000000ee00eee000000000000000000000000eee000000000000eee00000000000000000000
-- 032:000000000000000000000000000000fff0000eeeeeeff000000000000ee000000ee000000000000000000ff00000000000e0000000000000000000000000000000000000000000ff000ff0000f0000000e0000000ee00ee00000000000000000000000eeee00000000000eeee00000000000000000000000
-- 033:000000000000000000000000000000000ffff0000eeeeeff00000000000eee00000ee000000000000000000f00000000000e00000000000000000000000000000000000000000ff000ff0000f000000ee000000ee00ee0000000000000000000000eee00000000000eeee000000000000000000000000000
-- 034:0000000000000000000000000000000000000fff0000eeeeeef00000000000ee00000ee000000000000000000000000000000000000000000000000000000000000000000000f0000f0000ff00000ee000000ee00ee000000000000000000000eee00000000000eee0000000000000000000000000000000
-- 035:fffff00000000000000000000000000000000000ffff000eeeeeef0000000000eee0000ee00000000000000000000000000000000000000000000000000000000000000000000000f0000f000000e000000ee00ee00000000000000000000eee0000000000eeee0000000000000000000000000000000000
-- 036:ee000fffff0000000000000000000000000000000000fff000eeeeeef0000000000ee0000ee00000000000000000000000000000000000000000000000000000000000000000000f0000f00000ee00000ee00ee0000000000000000000eee000000000eeee00000000000000000000000000000000000000
-- 037:00eeeeee00fffff00000000000000000000000000000000ffff00eeeeeef000000000ee0000ee0000000000000000000000000000000000000000000000000000000000000000000000000000e00000ee00ee000000000000000000eee00000000eeee000000000000000000000000000000000000000000
-- 038:00000000eeeee00fffff0000000000000000000000000000000fff000eeeeef00000000eee00000000000000000000000000000000000000000000000000000000000000000000000000000ee0000ee00ee0000000000000000eeee00000000eee0000000000000000000000000000000000000000000000
-- 039:0000000000000eeeeee0ffffff0000000000000000000000000000ffff00eeeeef00000000ee00000000000000000000000000000000000000000ccc00000000000000000000000000000ee0000ee00ee000000000000000eee00000000eeee0000000000000000000000000000000000000000000000000
-- 040:0000000000000000000eeeee00fffff000000000000000000000000000fff00eeeeef0000000ee0000000000000000000000000000000000000ccccccc00000000000000000000000000e0000ee000000000000000000eee0000000eeee00000000000000000000000000000000000000000000000000000
-- 041:000000000000000000000000eeeeee0fffff0000000000000000000000000fff00eeeeef0000000000000000000000000000000000000000000ccccccc000000000000000000000000000000e00000000000000000eee000000eeee000000000000000000000000000000000000000000000000000000000
-- 042:000000000000000000000000000000eeeeeefffff00000000000000000000000ffff00eeeef000000000000000000000000000000000000000ccccccccc00000000000000000000000000000000000000000000eee000000eee0000000000000000000000000000000000000000000000000000000000000
-- 043:000000000000000000000000000000000000eeeeeffffff000000000000000000000fff00eeef0000000000000000000000000000000000000ccccccccc00000000000000000000000000000000000000000eee00000eeee0000000000000000000000000000000000000000000000000000000000000000
-- 044:00000000000000000000000000000000000000000eeeeeefffff0000000000000000000ffff0eee00000000000000000000000000000000000ccccccccc0000000000000000000000000000000000000eeee0000eeee00000000000000000000000000000000000000000000000000000000000000000000
-- 045:00000000000000000000000000000000000000000000000eeeeefffff000000000000000000fff0eee000000000000000000000000000000000ccccccc00000000000000000000000000000000000eee0000eeee000000000000000000000000000000000000000000000000000000000000000000000000
-- 046:0000000000000000000000000000000000000000000000000000eeeeeffffff000000000000000ffffeeee00000000000000000000000ccc000ccccccc00000000000000000000000000000000eee00000ee0000000000000000000000000000000000000000000000000000000000000000000000000000
-- 047:0000000000000000000000000000000000000000000000000000000000eeeeefffff00000000000000ff00eee000000000000000000ccccccccc0ccc00000000000000000000000000000000ee000000000000000cccccccc000000000000000000000000000000000000000000000000000000000000000
-- 048:000000000000000000000000000000000000000000000000000000000000000eeeeefff000000000000000000ee0000000000000000ccccccccccc00000ccc00000000000c0000ccccccccccccccccccccccccccc00000cc0000000000000000000000000000000000000000000000000000000000000000
-- 049:eeeeeeeeeee0000000000000000000000000000000000000000000000000000000000eee0000000000000000000000000000000000cccccccccccc000ccccccc0000000cccccccccc000000000000000000000000000cc0000000000000000000000000000000000000000000000000000000fffffffffff
-- 050:00000000000eeeeeeeeeeeee0000000000000000000000000000000000000000000000000000000000000000000000000000000000ccccccccccccc00ccccccc00000cc0000c22222c000000000000000000000000cc0000000000000000000000000000000000000000000ffffffffffffff00000000000
-- 051:ffffff000000000000000000eeeeeeeeeeeee000000000000000000000000000000000000000000000000000000000000000000000ccccccccccccc0ccccccccc00cccccccc2222222c000000000000000000000cc00000000000000000000000000000000fffffffffffff0000000000000000000000000
-- 052:000000fffffffffffffffffff000000000000eeeeeeeeeeeee000000000000000000000000000000000000000000000000000000000cccccccccccc0ccccccccc0cc00000c222222222cccccc00000000000000cc0000000000000000000ffffffffffffff00000000000000000000000000000000000000
-- 053:0000000000000000000000000fffffffffffffffffff000000eeeeeeeeeeeeee000000000000000000000000000000000ccc0000000ccccccccccc00cccccccccccc00000c222222222c00000cccccccccc00cc00000000fffffffffffff0000000000000000000000000000000000000000000000000000
-- 054:00000000000000000000000000000000000000000000ffffffffffffffffff00eeeeeeeeeeeee000000000000000000ccccccc0000000ccccccccc000cccccccc000ccc00c222222222c0000000000000ffccffffffffff000000000000000000000000000000000000000000eeeeeeeeeeeeeeeeeeeeeee
-- 055:00000000000000000000000000000000000000000000000000000000000000ffffffffff00000eeeeeee00000000000ccccccc00000000000ccc00000ccccccc0000000ccc222222222c000000fffffffcc000000000000000000000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee00000000000000000000000
-- 056:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee000000000000000000000000000000000000000000000000000ccccccccc00000000000000000000ccccc000000000c2cc222222c000000000000c000000eeeeeeeeeeeeeeeee00000000000000000000000000000000000000000000000000000000
-- 057:00000000000000000000000000000000000000000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee0000000000000000ccccccccc000000000000000000cc0000cc000000000c22cccc2c0000000000ccc00000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 058:0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ccccccccc00ccccc0000ccc00cc0c000000cc000cccccc22222ccc0000000cc00000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 059:00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ccccccc00ccccccc00c222cc000c00000000c0cccccccccccc000cccc0ccfffffff000000000000000000000000000000000000000000000000000000000000000000000000000000
-- 060:00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ccccccc0cccccccccc2222cc0000c0000000cccccccccc00000000000cc00000000ffffffffffffffffff000000000000000000000000000000000000000000000000000000000000
-- 061:0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ccc00ccccccccccc2222cc0000c0000000ccccccccccc00000000ccff00000000000000000000000000fffffffffffffffff0000000000000000000000000000000000000000000
-- 062:0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ccc00ccccccccccc2222cc00000c000000ccccccccccc000000cc0000ffffffff00000000000000000000000000000000000fffffffffffffffff00000000000000000000000000
-- 063:00000000000000000000000000000000000000000000000000000000000000000000000000000000eeee00000000000ccccccccccccccccccc222c000000c000000ccccccccccc0000cc00000000000000ffffffff00000000000000000000000000000000000000000000ffffffffffffffffff00000000
-- 064:0000000000000000000000000000000000000000000000000000000000000000000000000eeeeeee000000000000000ccccccccccccccccccccccc0000000c00000ccccccccccc00ccccc000000000eee000000000ffffffff000000000000000000000000000000000000000000000000000000ffffffff
-- 065:000000000000000000000000000000000000000000000000000000000000000000eeffffe000000000000fff000000ccccccccccccccccccc0000c0000000c00000ccccccccccc0ccccccc0000000fff0eeeeee0eeee000000ffffffff000000000000000000000000000000000000000000000000000000
-- 066:00000000000000000000000000000000000000000000000000000000000eefffffff0000000000000ffff000000000ccccccccccccccccccc0000c00000000c00000ccccccccccccccccccc000000000ffff000eeeeeeeeeee00000000ffffffff0000000000000000000000000000000000000000000000
-- 067:0000000000000000000000000000000000000000000000000000eeeffffff000000000000000fffff0000000000000ccccccccccccccccc0c00000c0000000c000000ccccccccccccccccccc000000000000fffff0000eeeeeeeeeee0000000000ffffffff00000000000000000000000000000000000000
-- 068:0000000000000000000000000000000000000000000000eefffffff0000000000000000fffff0000000000000000000ccccccccccccccc0c000000c00000000c000000ccccc00ccccccccccc00000000000000000fffff00000eeeeeeeeeee000000000000ffffffff000000000000000000000000000000
-- 069:000000000000000000000000000000000000000eefffffff0000000000000000000ffff000000000000000000000000ccccccccccccccccccc0ccccc00000000c0000000c0000ccccccccccc000eee0000000000000000ffff0000000eeeeeeeeeee00000000000000ffffffff0000000000000000000000
-- 070:00000000000000000000000000000000eefffffff000000000000000000000fffff0000000000000000000000ee000000ccc0cccccccccccccccccccc0000000c00000cc00000ccccccccccc00000eeeeee000000000000000fffff00000000eeeeeeeeeee0000000000000000ffffffff00000000000000
-- 071:0000000000000000000000000eeeffffff000000000000000000000000ffff0000000000000000000000000ee000000000000ccccccccccccccccccccc0ccc000c0ccc0000000ccccccccccc000000eeeeeeee00ff0000000000000fffff000000000eeeeeeeeeee000000000000000000ffffffff000000
-- 072:000000000000000000eeefffffff0000000000000000000000000fffff00000000000000000000000000eee00000000000000c0ccccccccccccccccccccccccc0cc00000000cccccccccccc000000000eeeeeeeeeeffff00000000000000ffff00000000000eeeeeeeeeee00000000000000000000ffffff
-- 073:00000000000eeefffffff000000000000000000000000000fffff00000000000000000000000000000ee00000000000000000c00c0ccccccccccccccccccccccccc0000000cccccccccccc000000000ff00eeeeeeeeee0ffff00000000000000fffff000000000000eeeeeeeeeeee0000000000000000000
-- 074:0000eeefffffff000000000000000000000000000000ffff00000000000000000000000000000000ee00ff00000000000000c000c0ccccccccccccccccccccccccc000000cccccccccccc000000000000ff000eeeeeeeeee00fff0000000000000000fffff0000000000000eeeeeeeeeeee0000000000000
-- 075:effffff00000000000000000000000000000000fffff000000000000000000000000000000000eee00ff000000000000000c0000c0ccccccccccccccccccccc00ccc0000ccccccccccc00000000000000eefff000eeeeeeeeee00ffff00000000000000000ffff000000000000000eeeeeeeeeeee0000000
-- 076:f0000000000000000000000000000000000ffff000000000000000000000000000000000000ee000ff0000000f0000e000c0000c00ccccccccccccccccccc00000cc0000ccccccccccc0000000000000000ee0fff000eeeeeeeeee000ffff00000000000000000fffff0000000000000000eeeeeeeeeeee0
-- 077:000000000000000000000000000000fffff0000000000000000000000000000000000000eee000ff0000000ff000ee0000c0000c000cccccccccccccccc00cc0c0ccc000ccccccccccc000000000000000000ee00ff0000eeeeeeeeeee000ffff000000000000000000fffff00000000000000000eeeeeee
-- 078:0000000000000000000000000fffff0000000000000000000000000000000000000000ee0000ff00000e0ff0000ee0000c0000c00000cccccccccccccc0ccdddc00cc000ccccccccccc000000000000000ee000eee0fff0000eeeeeeeeeee0000fff00000000000000000000ffff0000000000000000000e
-- 079:000000000000000000000ffff000000000000000000000000000000000000000000eee0000ff00000ee0f00000ee0000cc000c000000cccccc0ccccc000dddddcc000c00ccccccccccc00000000000000000ee0000ee00ff00000eeeeee0eeee0000ffff00000000000000000000fffff000000000000000
-- 080:0000000000000000fffff00000000000000000000000000000000000000000000ee00000ff00000ee0ff0000eee0000c00000ccc0000c000000ccccc00cdddddcc0000c00ccccccccc00000000000000000000ee0000ee00fff00000eeeeee0eeee00000ffff000000000000000000000fffff0000000000
-- 081:000000000000ffff0000000000000000000000000000000000000000000000eee00000ff00000ee0ff00000ee000000c000ccccccc0c00000cc00ccc0cdddddddc0000c000ccccccc00000000000000000000000ee0000eee00ff000000eeeeee0eeee000000fff00000000000000000000000ffff000000
-- 082:0000000fffff000000000000000000000000000000000000000000000000ee000000ff000000e00f00000eee000000c0000ccccccc0c0000cc0000cc0ccddddddcc0000c000ccccc00000000000000000000000000ee00000ee00fff000000eeeeee00eeee00000ffff00000000000000000000000fffff0
-- 083:00fffff000000000000000000000000000000000000000000000000000ee000000ff000000ee0ff00f00eee0000000c000cccccccccc00cc000000cc0ccddddddcc0000c000000000000000000000000000000000000ee00000ee000fff000000eeeeeee0eeee000000ffff000000000000000000000000f
-- 084:ff00000000000000000000000000000000000000000000000000000eee000000ff000000ee0ff00ff0eee00000000c0000cccccccccccc00000000cc0ccddddeeecc0000c000000000000f00e000000000000000000000ee00000eee000ff0000000ee00eee0eeee0000000ffff000000000000000000000
-- 085:00000000000000000000000000000000000000000000000000000ee0000000ff000000ee00f000f00eee00000000c00000cccccccccc0000000000cc0ccdddeeeecc0000c0000000000000f00e0000000000000000000000ee000000ee000fff000000eee00eee0eeee00000000fff000000000000000000
-- 086:00000000000000000000000000000000000000000000000000eee0000000ff000000ee00ff00ff00eee0e000000c00000ccccccccc000000000000cc00cdeeeeeddcc0f00c0000e00000000f00ee0000000000000000000000ee000000ee0000ff0000000eee00eee00eeee0000000ffff00000000000000
-- 087:000000000000000000000000000000000000000000000000ee00000000ff0000000e00ff000f00eee00e0000000c00000cfccccccc000000000000cc00ceeeeddddcc00f00c0000e00000000f000e00000000000000000000000ee000000eee000fff0000000eee00eee00eeee00000000ffff0000000000
-- 088:00000000000000000000000000000000000000000000000000000000ff0000000000000000000e0000000000000000000000cccc000000000000000000cceddd000cc00000000000e0000000000000000000000000000000000000000000000ee00000000000000000000000000ee000000000fff0000000
-- 089:0000000000000000000000000cccccccccccccccccccccccc00000ff000ccccccccccccccc00e00ccccccccccccccccccc0000000c000000000ccccc00ccddd00c0000ccccccc000e00000cccccccccccccccccccc00000cccccccccccccc0000ee000cccccccccccccccccccc000eee000000000ffff000
-- 090:000000000000000000000000caaaaaaaaaaaaaaaaaaaaaaaac00ff0000caaaaaaaaaaaaaa9c000caaaaaaaaaaaaaaaaaa9c00000cac0f00000caaaa9c0ccdd00cac00c9aaaaaac000e000c9aaaaaaaaaaaaaaaaaa9c000caaaaaaaaaaaaaac00000e0c9aaaaaaaaaaaaaaaaaa9c0e000eee0000000000fff
-- 091:00000000000000000000000caaaaaaaaaaaaaaaaaaaaaaaaaac0000000caaaaaaaaaaaaa9c000caaaaaaaaaaaaaaaaaa9c00000caac0f0000caaaa9c00ccd00caac000c9aaaaaac000e000c9aaaaaaaaaaaaaaaa9c000caaaaaaaaaaaaaaaac0000000c9aaaaaaaaaaaaaaaa9c000eee000eeee000000000
-- 092:0000000000000000000000caaaaaaaaaaaaaaaaaaaaaaaaaaac0000000caaaaaaaaaaaa9c0000caaaaaaaaaaaaaaaaa9c00000caaac00000caaaa9c000cc00caaac0000c9aaaaaac000e000c9aaaaaaaaaaaaaa9c0000caaaaaaaaaaaaaaaaac0000000c9aaaaaaaaaaaaaa9c00eee00eee0000eee000000
-- 093:000000000000000000000c99999999999999999999999aaaaac00000e0c999999999999c000e0caaaaa999999999999c00000caaaac0000caaaa9c0000cc0caaaac00000c999aaaac000e000c99999999999999c00000caaaaa9999999999999c0000000c99999aaaa99999c000000eee00eee0000eee000
-- 094:0000000000000000000000ccccccccccccccccccccccc9aaaac000ee000cccccccccccc000e00caaaa9cccccccccccc000000caaaac000caaaa9c00e000c0caaaac000000ccc9aaaac00e0000cccccccccccccc000000caaaa9ccccccccccccc00ee00000cccccaaaaccccc0000000000eee00eee0000eee
-- 095:000000000000000000000000000000000000000000000caaaac00e000f000000000000000e000caaaac000000000000000000caaaac00caaaa9c000c000c0caaaac00cc00000c9aaaac00e00000000000000000000000caaaac00000000000000000eee000000caaaac00000f00000000000eee00eee0000
-- 096:00000000000000000000000000ee000000000000ff00caaaa9c0e00f000000000000000ee0000caaaac00ccc000f000000000caaaac0caaaa9c0000c000c0caaaac000000000caaaa9c000e0000000000000000e00000caaaac00000000000000000000ee0000caaaac000000fff00000000000eee00eee0
-- 097:00000000000000000000000eee0000c0000000ff000caaaa9c0000f00cccccccccccc00000000caaaac0cc00000f000000000caaaaccaaaa9c00000c00000caaaaccccccccccaaaa9c00000e000cccccccccc000e0000caaaaacccccccccccccc00000000ee00caaaac0ee000000fff00000000000eee00e
-- 098:000000000000000000000ee000000cac0000ff0000caaaa9c000ff00caaaaaaaaaaaac0000000caaaac0000000f0000000000caaaaaaaaa9c000000c00000caaaaaaaaaaaaaaaaa9c000000e00caaaaaaaaaac000e000caaaaaaaaaaaaaaaaaaac000000000e0caaaac000ee0000000ff000000000000eee
-- 099:0000000000000000000ee00000000caac00f00000caaaa9c00ff000caaaaaaaaaaaaac0000000caaaac000000f00000000000caaaaaaaaac0000000c00000caaaaaaaaaaaaaaaa9c00000000e0caaaaaaaaaac0000e00caaaaaaaaaaaaaaaaaaaac0000000000caaaac00000eee000000fff000000000000
-- 100:0000000000000000eee0000000000caaac000000caaaa9c00f0000caaaaaaaaaaaaaac0000000caaaac000000f000000000e0caaaaaaaaac0000000c000c0caaaaaaaaaaaaaaa9c00e00000000caaaaaaaaaac0f000e0c9aaaaaaaaaaaaaaaaaaac0000000000caaaac00000000ee0000000ff0000000000
-- 101:00000000000000ee0000000000000caaaac0000caaaa9c00f0000c999999999999999c0000000caaaac00000f0000000000e0caaaa99aaaac000000c0cce0caaaa99999999999c00f0e0000000c9999999999c00f00000c99999999999999aaaaac0000000000caaaac0000000000ee0000000fff0000000
-- 102:00000000000eee000000000000000caaaac000caaaa9c000000000ccccccccccccccc00000000caaaac0000f0000000000ef0caaaacc9aaaac00000cccee0caaaaccccccccccc00ef0e00000000cccccccccc0000f00000cccccccccccccc9aaaac0000000000caaaac0e0000000000eee0000000ff00000
-- 103:000000000ee000000000000000ff0caaaac00caaaa9c0000000ff000000000000000000000000caaaac000f00000000000ef0caaaac0c9aaaac0000ce0ee0caaaac000000000000fef0e0000000000000000000000ff00000000000000000caaaac0000000000caaaac00ee00000000000ee0000000fff00
-- 104:000000eee000000000000000ff000caaaac0caaaa9c0000000000000000000000000000000000caaaac00000000000000ef00caaaac00c9aaaac000ce0ee0caaaac00000f000fe0fef00e00000000000000000000000f0000000000000000caaaac0000000000caaaac0000ee00000000000ee00000000ff
-- 105:0000ee0000000000000000ff00000caaaaacaaaa9c0000000cccccccccccccccccccccc000000caaaaacccccccccccc00eff0caaaac000c9aaaac00ee0ee0caaaac00000f000fe00fef0e0000cccccccccccc000000000cccccccccccccccaaaaac0000000000caaaac000000ee00000000000eee0000000
-- 106:0eee0000000000000000ff0000000caaaaaaaaa9c0000000caaaaaaaaaaaaaaaaaaaaaac00000caaaaaaaaaaaaaaaaac000e0c9aaac0000c9aaaac00e0ee0c9aaac000000f000fe0fef00e00caaaaaaaaaaaac0000000c9aaaaaaaaaaaaaaaaaaac0000000000caaa9c00000000ee000000000000ee00000
-- 107:e00000000000000000ff000000000caaaaaaaa9c0000000caaaaaaaaaaaaaaaaaaaaaaaac0000caaaaaaaaaaaaaaaaaac00e00c9aac00000c9aaaac000ee00c9aac000000f000fe00fef000caaaaaaaaaaaaaac0000000c9aaaaaaaaaaaaaaaaaac0000000000caa9c00000000000ee000000000000ee000
-- 108:0000000000000000ff00000000000c9aaaaaa9c0000000caaaaaaaaaaaaaaaaaaaaaaaaaac000c9aaaaaaaaaaaaaaaaaac00000c9ac000000c9aaaac00e0e00c9ac000000f000f0e0fe000caaaaaaaaaaaaaaaac0000000c9aaaaaaaaaaaaaaaa9c0000000000ca9c00000000000000ee000000000000eee
-- 109:00000000000000ff00000000000000c999999c0000ff0c9999999999999999999999999999c000c9999999999999999999c00f00c9c0000000c99999c00ee000c9c0000000f000fe00fe0c999999999999999999c0000000c9999999999999999c00000000000c9c00000000000000000ee0000000000000
-- 110:000000000000ff000000000000ee000cccccc0000f0000cccccccccccccccccccccccccccc00000ccccccccccccccccccc000f000c000000000ccccc000ee0e00c00000000f000fe00fe00cccccccccccccccccc000000000cccccccccccccccc0000000000000c00000000000000000000ee00000000000
-- 111:000000000fff000000000000ee0000000000000ff00000000000000000000000000000000000000000000000000000000000ff00000000000e000000000ee0e000000000000f000fe00fe00000000000000000000000000000000000000000000000000000000000000000000000000000000ee000000000
-- 112:0000000ff0000000000000ee00000f00000000f0000eee0e000e0000000000000000000000000000f0000000000000ef0e00f000000000000e00000ee00ee0e000000000000f000fe00fe0f00e000000000e0000e000000000000f0000e00000000000000000000000000000000000000000000eee000000
-- 113:00000ff00000000000000e00000ff0000000ff0000ee00e000e0000000000000000000000000000f0000000000000ef0ee00f000000000000e00000ee00ee0e000000000000f0000fe00fef00e000000000e00000e000000000000f0000e0000000000000000000000000000000000000000000000ee0000
-- 114:000ff00000000000000ee0000ff00000000f00000ee0ee000e0000000000000000000000000000f00000000000000ef0ee0f000000000000e000000ee00ee0e0000000000000f000fe00fe0f00e000000000e00000e000000000000f0000ee0000000000000000000000000000000000000000000000ee00
-- 115:0ff00000000000000ee00000f00000000ff0000ee00e000ee00000000000000000000000000000f0000000000000ef0fe00f000000000000e000000ee00ee00e000000000000f0000fe00fef00e0000000000e00000e000000000000f00000e00000000000000000000000000000000000000000000000ee
-- 116:f00000000000000ee00000ff00000000f00000ee00e000e000000000000000000000000000000f00000000000000ef0ee0ff000000000000e000000ee00ee00e000000000000f0000fe00f0ef00e0000000000e00000e000000000000f00000e000000000000000000000000000000000000000000000000
-- 117:00000000000000e00000ff00000000ff0000eee0ee000e000000000000000000000000000000f00000000000000e0ffe00f0000000000000e000000ee00ee00e0000000000000f000f0e00fe0f00e0000000000e00000e000000000000f00000e00000000000000000000000000000000000000000000000
-- 118:000000000000ee00000f000000000f00000ee00e0000e000000000000000000000000000000f000000000000000ef0ee00f0000000000000e000000ee00ee00e0000000000000f0000fe00f0ef00e0000000000e000000e000000000000f00000ee000000000000000000000000000000000000000000000
-- 119:0000000000ee00000ff000000000f00000ee00e000ee0000000000000000000000000000000f00000000000000e0f0ee0ff0000000000000e000000ee00ee00e0000000000000f0000fe000fe0f00e0000000000e000000e000000000000ff00000e00000000000000000000000000000000000000000000
-- 120:00000000ee00000ff000000000ff0000eee0ee000e00000000000000000000000000000000f000000000000000ef0ee00f00000000000000e000000ee00ee00e00000000000000f0000fe00f0ef000e0000000000e00000e00000000000000f00000e0000000000000000000000000000000000000000000
-- 121:000000ee000000f0000000000f00000ee00e0000e00000000000000000000000000000000f000000000000000e0f0ee00f00000000000000e000000ee00ee00e00000000000000f0000fe000fe0f00e00000000000e00000e00000000000000f00000e000000000000000000000000000000000000000000
-- 122:00000e000000ff000000000ff0000eee00e0000e00000000000000000000000000000000f0000000000000000ef0fe00ff00000000000000e000000ee00e0e0e00000000000000f00000fe00f0ef000e0000000000e000000e00000000000000f00000e00000000000000000000000000000000000000000
-- 123:000ee00000ff0000000000f00000eee0ee000ee000000000000000000000000000000000f0000000000000000ef0ee00f00000000000000e0000000ee00e0e00e00000000000000f0000fe000fe0f00e00000000000e000000e00000000000000f00000ee000000000000000000000000000000000000000
-- 124:0ee000000f0000000000ff00000ee00e0000e0000000000000000000000000000000000f0000000000000000ef00ee00f00000000000000e0000000ee000ee00e00000000000000f00000fe00f0ef000e00000000000e000000e00000000000000f000000e00000000000000000000000000000000000000
-- 125:e000000ff0000000000f00000eee00e0000e0000000000000000000000000000000000f00000000000000000ef0ee00ff00000000000000e0000000ee000ee00e000000000000000f0000fe000fe0f000e00000000000e000000e00000000000000f000000e0000000000000000000000000000000000000
-- 126:00000ff0000000000ff00000ee000e0000e00000000000000000000000000000000000f0000000000000000e0f0ee00f000000000000000e0000000ee000ee00e000000000000000f00000fe00f0e0f00e000000000000e000000e00000000000000ff00000e000000000000000000000000000000000000
-- 127:0000f00000000000f00000eee00ee000ee00000000000000000000000000000000000f00000000000000000ef0ee000f000000000000000e0000000ee000ee00e000000000000000f00000fe000fe0f000e00000000000e0000000e000000000000000f00000e00000000000000000000000000000000000
-- 128:00ff0000000000ff00000eee00e0000e000000000000000000000000000000000000f00000000000000000e0f0ee00ff000000000000000e0000000ee000ee00e0000000000000000f0000fee00f0e0f00e000000000000e0000000e000000000000000f00000ee000000000000000000000000000000000
-- 129:ff00000000000f000000ee000e0000e000000000000000000000000000000000000f000000000000000000ef0fee00f0000000000000000e0000000ee000ee00e0000000000000000f00000fe000fe0f000e000000000000e0000000e000000000000000f000000e00000000000000000000000000000000
-- 130:00000000000ff00000eee00ee0000e0000000000000000000000000000000000000f00000000000000000e0f0ee00ff0000000000000000e0000000ee000ee00e0000000000000000f00000fe000f0e0f000e000000000000e000000e0000000000000000f000000e0000000000000000000000000000000
-- 131:0000000000f000000eee00e0000ee0000000000000000000000000000000000000f000000000000000000ef00ee00f0000000000000000e00000000ee000ee00e00000000000000000f00000fe000f0ef000e0000000000000e000000e0000000000000000f000000e000000000000000000000000000000
-- 132:00000000ff00000eee000e0000e00000000000000000000000000000000000000f000000000000000000e0f0ee000f0000000000000000e00000000ee000ee000e0000000000000000f00000fe000f0e0f000e000000000000e0000000e0000000000000000f000000ee0000000000000000000000000000
-- 133:0000000f000000e0e00ee0000e00000000000000000000000000000000000000f0000000000000000000ef00ee00ff0000000000000000e00000000ee000ee000e0000000000000000f000000fe000f0ef000e0000000000000e0000000e0000000000000000f0000000e000000000000000000000000000
-- 134:00000ff000000eee00e00000e000000000000000000000000000000000000000f000000000000000000e0f0e0e00f00000000000000000e00000000ee000ee000e00000000000000000f00000fe000f0e0f000e0000000000000e0000000e0000000000000000ff000000e00000000000000000000000000
-- 135:0000f000000eee000e0000ee000000000000000000000000000000000000000f0000000000000000000e0f0ee000f00000000000000000e00000000ee000ee000e00000000000000000f000000fe000f0e0f000e0000000000000e0000000e00000000000000000f000000e0000000000000000000000000
-- </SCREEN>

-- <PALETTE>
-- 000:1a1c2c5d275db13e53ef7d57ffcd75a7f07038b76425717929366f3b5dc941a6f673eff7f4f4f494b0c2566c86333c57
-- </PALETTE>


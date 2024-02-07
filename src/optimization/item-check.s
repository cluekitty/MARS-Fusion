; Optimizes the size of item collection info in memory.
; The arrays of room IDs and item positions are replaced with a bit array,
; with room IDs and item positions stored in ROM instead.
; This patch saves a significant amount of memory, freeing up large chunks in
; both external WRAM and SRAM.

.autoregion
; Gets the range of item indices found in the currently loaded room.
; The start index is in r0, and the (exclusive) end index is in r1.
; The indices will be numbers from 0 to 99, else they will both be 0.
	.align 2
.func GetRoomItems
	ldr		r1, =CurrArea
	ldrb	r0, [r1]
	ldrb	r1, [r1, CurrRoom - CurrArea]
	ldr		r2, =@ItemsByArea
	lsl		r0, #2
	ldr		r2, [r2, r0]
	; binary search for room id
	; r1 = target, r2 = curr ptr
	ldrb	r0, [r2, #8]
	cmp		r0, r1
	bgt		@@bsearch_1
	add		r2, #8
@@bsearch_1:
	ldrb	r0, [r2, #4]
	cmp		r0, r1
	bgt		@@bsearch_2
	add		r2, #4
@@bsearch_2:
	ldrb	r0, [r2, #2]
	cmp		r0, r1
	bgt		@@bsearch_3
	add		r2, #2
@@bsearch_3:
	ldrb	r0, [r2, #1]
	cmp		r0, r1
	bgt		@@bsearch_4
	add		r2, #1
@@bsearch_4:
	ldrb	r0, [r2]
	cmp		r0, r1
	bne		@@fail
	add		r2, #16
	ldrb	r0, [r2, MinorLocation_XPos]
	ldrb	r1, [r2, MinorLocation_YPos]
	bx		lr
	.pool
@@fail:
	mov		r0, #0
	mov		r1, #0
	bx		lr
.endfunc
.endautoregion

.autoregion
; Gets the index of the passed collectible item in the currently loaded room.
; This index will be a number from 0 to 99 if found, else it will be -1.
	.align 2
.func GetItemIndex
	; r0 = x pos, r1 = y pos
	push	{ r4, lr }
	lsl		r4, r1, #8h
	orr		r4, r0
	bl		GetRoomItems
	cmp		r0, r1
	beq		@@fail
	lsl		r2, r1, #2
	lsl		r1, r0, #2
@@lsearch:
	ldr		r3, =@ItemPositions
	; r1 = offset, r2 = end offset, r3 = array, r4 = position
	ldrh	r0, [r3, r1]
	cmp		r0, r4
	beq		@@success
	add		r1, #4
	cmp		r1, r2
	blt		@@lsearch
@@fail:
	mov		r0, #0
	mvn		r0, r0
	b		@@exit
	.pool
@@success:
	lsr		r0, r1, #2
@@exit:
	pop		{ r4, pc }
.endfunc
.endautoregion

.autoregion
	.align 2
.func IsItemCollected
	ldr		r2, =TanksCollected
	lsl		r1, r0, #3
	ldrb	r2, [r2, r1]
	lsl		r0, #29
	lsr		r0, #29
	mov		r1, #1
	lsl		r1, r0
	and		r2, r1
	bx		lr
	.pool
.endfunc
.endautoregion

.org SetTankAsCollected
.area 84h
	push	{ lr }
	bl		GetItemIndex
	cmp		r0, #0
	blt		@@exit
	ldr		r2, =TanksCollected
	lsr		r3, r0, #3
	lsl		r0, #29
	lsr		r0, #29
	mov		r1, #1
	lsl		r1, r0
	ldrb	r0, [r2, r3]
	orr		r0, r1
	strb	r0, [r2, r3]
@@exit:
	pop		{ pc }
	.pool
.endarea

.org RemoveCollectedTanks
.area 0CCh
	push	{ r4-r7, lr }
	ldr 	r0, =NonGameplayFlag
	ldrb	r0, [r0]
	cmp		r0, #0
	bne		@@exit
	bl		GetRoomItems
	cmp		r0, r1
	beq		@@exit
	mov		r4, r0
	mov		r5, r1
	ldr		r6, =TanksCollected
	ldr		r7, =@ItemPositions
@@loop:
	lsr		r2, r4, #3
	lsl		r1, r4, #29
	lsr		r1, #29
	add		r1, #1
	ldrb	r0, [r6, r2]
	lsr		r0, r1
	bcc		@@loop_inc
	; item collected, delete from the loaded map
	lsl		r2, r4, #2
	add		r2, r7
	ldrb	r0, [r2, MinorLocation_YPos]
	ldr		r3, =LevelData
	ldrh	r1, [r3, LevelData_Clipdata + LevelLayer_Stride]
	mul		r0, r1
	ldrb	r1, [r2, MinorLocation_XPos]
	add		r0, r1
	lsl		r2, r0, #1
	ldr		r1, [r3, LevelData_Bg1 + LevelLayer_Data]
	mov		r0, #0
	strh	r0, [r1, r2]
	ldr		r3, [r3, LevelData_Clipdata + LevelLayer_Data]
	ldrh	r0, [r3, r2]
	ldr		r1, =SpecialTileset
	ldrh	r1, [r1, r0]
	sub		r1, #2Ah
	cmp		r1, #2
	bhi		@@set_bg1_zero
	ldr		r0, =#802Ch
	b		@@set_bg1
@@set_bg1_zero:
	mov		r0, #0
@@set_bg1:
	strh	r0, [r3, r2]
@@loop_inc:
	add		r4, #1
	cmp		r4, r5
	blt		@@loop
@@exit:
	pop		{ r4-r7, pc }
	.pool
.endarea

.org MinimapSetCollectedItems
; get all items in area and mark them as collected on the minimap
; takes area as an argument
.area 0A4h
	push	{ r4-r7, lr }
	mov		r5, r8
	push	{ r5 }
	ldr		r1, =@ItemsByArea
	lsl		r0, #2
	ldr		r6, [r1, r0]
	ldr		r7, =AreaLevels
	ldr		r7, [r7, r0]
@@loop:
	ldrb	r2, [r6]
	cmp		r2, #0FFh
	beq		@@exit
	mov		r8, r2
	ldrb	r3, [r6, #16]
	lsr		r0, r3, #3
	ldr		r1, =TanksCollected
	ldrb	r0, [r1, r0]
	lsl		r1, r3, #29
	lsr		r1, #29
	add		r1, #1
	lsr		r0, r1
	bcc		@@loop_inc
	ldr		r5, =@ItemPositions
	lsl		r0, r3, #2
	add		r5, r0
	ldrb	r0, [r5, MinorLocation_XPos]
	sub		r0, #2
	mov		r1, #15
	bl		Divide
	mov		r4, r0
	ldrb	r0, [r5, MinorLocation_YPos]
	sub		r0, #2
	mov		r1, #10
	bl		Divide
	mov		r5, r0
	mov		r0, r8
	mov		r1, #60
	mul		r0, r1
	add		r3, r7, r0
	add		r3, #LevelMeta_MapX
	ldrb	r0, [r3, LevelMeta_MapY - LevelMeta_MapX]
	add		r0, r5
	lsl		r0, #5
	add		r0, r4
	ldrb	r1, [r3]
	add		r0, r1
	lsl		r0, #1
	ldr		r3, =MinimapData
	ldrh	r1, [r3, r0]
	add		r1, #1
	strh	r1, [r3, r0]
@@loop_inc:
	add		r6, #1
	b		@@loop
	.pool
@@exit:
	pop		{ r5 }
	mov		r8, r5
	pop		{ r4-r7, pc }
.endarea

.org MapScreenCountTanks
.area 13Ch
	push	{ r4-r5, lr }
	ldr		r5, =TankCounter
	mov		r0, #20
	strb	r0, [r5, TankCounter_MaxTotalEnergyTanks]
	mov		r0, #48
	strb	r0, [r5, TankCounter_MaxTotalMissileTanks]
	mov		r0, #32
	strb	r0, [r5, TankCounter_MaxTotalPowerBombTanks]
	ldr		r4, =SamusUpgrades
	ldrh	r0, [r4, SamusUpgrades_MaxEnergy]
	sub		r0, #99
	mov		r1, #100
	bl		Divide
	strb	r0, [r5, TankCounter_CurrTotalEnergyTanks]
	ldrh	r0, [r4, SamusUpgrades_MaxMissiles]
	sub		r0, #10
	mov		r1, #5
	bl		Divide
	strb	r0, [r5, TankCounter_CurrTotalMissileTanks]
	ldrb	r0, [r4, SamusUpgrades_MaxPowerBombs]
	sub		r0, #10
	lsr		r0, #1
	strb	r0, [r5, TankCounter_CurrTotalPowerBombTanks]
	ldr		r1, =@ItemsByArea
	ldr		r0, =CurrArea
	ldrb	r0, [r0]
	lsl		r0, #2
	ldr		r4, [r1, r0]
@@loop:
	ldrb	r2, [r4]
	cmp		r2, #0FFh
	beq		@@exit
	ldrb	r2, [r4, #16]
	lsr		r0, r2, #3
	ldr		r1, =TanksCollected
	ldrb	r0, [r1, r0]
	lsl		r1, r2, #29
	lsr		r1, #29
	lsr		r0, r1
	lsl		r0, #31
	lsr		r3, r0, #31
	ldr		r1, =@ItemPositions
	lsl		r0, r2, #2
	add		r1, r0
	ldrb	r0, [r1, MinorLocation_Upgrade]
	cmp		r0, Upgrade_MissileTank
	bne		@@checkETank
	ldrb	r0, [r5, TankCounter_MaxAreaMissileTanks]
	add		r0, #1
	strb	r0, [r5, TankCounter_MaxAreaMissileTanks]
	ldrb	r0, [r5, TankCounter_CurrAreaMissileTanks]
	add		r0, r3
	strb	r0, [r5, TankCounter_CurrAreaMissileTanks]
@@checkETank:
	cmp		r0, Upgrade_EnergyTank
	bne		@@checkPBTank
	ldrb	r0, [r5, TankCounter_MaxAreaEnergyTanks]
	add		r0, #1
	strb	r0, [r5, TankCounter_MaxAreaEnergyTanks]
	ldrb	r0, [r5, TankCounter_CurrAreaEnergyTanks]
	add		r0, r3
	strb	r0, [r5, TankCounter_CurrAreaEnergyTanks]
@@checkPBTank:
	cmp		r0, Upgrade_PowerBombTank
	bne		@@loop_inc
	ldrb	r0, [r5, TankCounter_MaxAreaPowerBombTanks]
	add		r0, #1
	strb	r0, [r5, TankCounter_MaxAreaPowerBombTanks]
	ldrb	r0, [r5, TankCounter_CurrAreaPowerBombTanks]
	add		r0, r3
	strb	r0, [r5, TankCounter_CurrAreaPowerBombTanks]
@@loop_inc:
	add		r4, #1
	b		@@loop
	.pool
@@exit:
	pop		{ r4-r5, pc }
	.pool
.endarea

; load entire table to SRAM instead of variable amount based on tanks collected
org 08080002h
.area 34h
	mov		r0, r8
	add		r1, r0, r7
	mov		r0, #10h
	str		r0, [sp]
	mov		r0, #3
	ldr		r2, =TanksCollected
	mov		r3, #(SaveData_Size - SaveData_TanksCollected) >> 4
	lsl		r3, #4
	bl		08002F1Ch
	b		08080036h
	.pool
.endarea

; init item collection info with 0s instead of 1s
.org 08080416h
	mov		r1, #0

.org 08080576h
	mov		r1, #0

.autoregion
	.align 4
.func InitializeSavedata
	push	{ r4, lr }
	sub		sp, #4
	ldr		r1, =SaveData
	ldr		r0, =SaveSlot
	ldrb	r0, [r0]
	lsl		r0, #2
	ldr		r4, [r1, r0]
	mov		r0, #10h
	str		r0, [sp]
	mov		r0, #3
	mov		r1, #0
	mov		r2, r4
	mov		r3, #300 >> 4
	lsl		r3, #4
	bl		08002FECh
	mov		r0, #3
	mov		r1, #0
	mov		r2, #SaveData_TanksCollected >> 4
	lsl		r2, #4
	add		r2, r4
	mov		r3, #(SaveData_Size - SaveData_TanksCollected) >> 4
	lsl		r3, #4
	bl		08002FECh
	add		sp, #4
	pop		{ r4, pc }
	.pool
.endfunc
.endautoregion

.org 0807F1BAh
	bl	InitializeSavedata
	b	0807F222h

.autoregion
.align 4
@ItemsByArea:
	.dw		@@Items_MainDeck
	.dw		@@Items_Sector1
	.dw		@@Items_Sector2
	.dw		@@Items_Sector3
	.dw		@@Items_Sector4
	.dw		@@Items_Sector5
	.dw		@@Items_Sector6
.endautoregion

; Sector items structure:
; - Sorted array of rooms containing items
; - Array of indices indicating the first item in each room, plus one extra
;   indicating the final item of the last room

.autoregion
@@Items_MainDeck:
	.db		07h, 11h, 23h, 26h, 2Dh, 2Fh, 32h, 33h
	.db		39h, 45h, 48h, 49h, 54h
	.fill	16 - (. - @@Items_MainDeck), 0FFh
	.db		(@Items_MainDeck_Room07 - @ItemPositions) >> 2
	.db		(@Items_MainDeck_Room11 - @ItemPositions) >> 2
	.db		(@Items_MainDeck_Room23 - @ItemPositions) >> 2
	.db		(@Items_MainDeck_Room26 - @ItemPositions) >> 2
	.db		(@Items_MainDeck_Room2D - @ItemPositions) >> 2
	.db		(@Items_MainDeck_Room2F - @ItemPositions) >> 2
	.db		(@Items_MainDeck_Room32 - @ItemPositions) >> 2
	.db		(@Items_MainDeck_Room33 - @ItemPositions) >> 2
	.db		(@Items_MainDeck_Room39 - @ItemPositions) >> 2
	.db		(@Items_MainDeck_Room45 - @ItemPositions) >> 2
	.db		(@Items_MainDeck_Room48 - @ItemPositions) >> 2
	.db		(@Items_MainDeck_Room49 - @ItemPositions) >> 2
	.db		(@Items_MainDeck_Room54 - @ItemPositions) >> 2
	.db		(@Items_Sector1_Room05 - @ItemPositions) >> 2
.endautoregion

.autoregion
@@Items_Sector1:
	.db		05h, 11h, 1Eh, 27h, 28h, 2Bh, 2Ch, 2Fh
	.db		32h, 34h
	.fill	16 - (. - @@Items_Sector1), 0FFh
	.db		(@Items_Sector1_Room05 - @ItemPositions) >> 2
	.db		(@Items_Sector1_Room11 - @ItemPositions) >> 2
	.db		(@Items_Sector1_Room1E - @ItemPositions) >> 2
	.db		(@Items_Sector1_Room27 - @ItemPositions) >> 2
	.db		(@Items_Sector1_Room28 - @ItemPositions) >> 2
	.db		(@Items_Sector1_Room2B - @ItemPositions) >> 2
	.db		(@Items_Sector1_Room2C - @ItemPositions) >> 2
	.db		(@Items_Sector1_Room2F - @ItemPositions) >> 2
	.db		(@Items_Sector1_Room32 - @ItemPositions) >> 2
	.db		(@Items_Sector1_Room34 - @ItemPositions) >> 2
	.db		(@Items_Sector2_Room06 - @ItemPositions) >> 2
.endautoregion

.autoregion
@@Items_Sector2:
	.db		06h, 09h, 0Ah, 11h, 15h, 19h, 1Bh, 1Fh
	.db		21h, 2Ah, 2Fh, 32h, 36h, 37h
	.fill	16 - (. - @@Items_Sector2), 0FFh
	.db		(@Items_Sector2_Room06 - @ItemPositions) >> 2
	.db		(@Items_Sector2_Room09 - @ItemPositions) >> 2
	.db		(@Items_Sector2_Room0A - @ItemPositions) >> 2
	.db		(@Items_Sector2_Room11 - @ItemPositions) >> 2
	.db		(@Items_Sector2_Room15 - @ItemPositions) >> 2
	.db		(@Items_Sector2_Room19 - @ItemPositions) >> 2
	.db		(@Items_Sector2_Room1B - @ItemPositions) >> 2
	.db		(@Items_Sector2_Room1F - @ItemPositions) >> 2
	.db		(@Items_Sector2_Room21 - @ItemPositions) >> 2
	.db		(@Items_Sector2_Room2A - @ItemPositions) >> 2
	.db		(@Items_Sector2_Room2F - @ItemPositions) >> 2
	.db		(@Items_Sector2_Room32 - @ItemPositions) >> 2
	.db		(@Items_Sector2_Room36 - @ItemPositions) >> 2
	.db		(@Items_Sector2_Room37 - @ItemPositions) >> 2
	.db		(@Items_Sector3_Room03 - @ItemPositions) >> 2
.endautoregion

.autoregion
@@Items_Sector3:
	.db		03h, 06h, 08h, 09h, 0Ch, 13h, 1Ch, 1Eh
	.db		21h, 22h, 23h, 25h
	.fill	16 - (. - @@Items_Sector3), 0FFh
	.db		(@Items_Sector3_Room03 - @ItemPositions) >> 2
	.db		(@Items_Sector3_Room06 - @ItemPositions) >> 2
	.db		(@Items_Sector3_Room08 - @ItemPositions) >> 2
	.db		(@Items_Sector3_Room09 - @ItemPositions) >> 2
	.db		(@Items_Sector3_Room0C - @ItemPositions) >> 2
	.db		(@Items_Sector3_Room13 - @ItemPositions) >> 2
	.db		(@Items_Sector3_Room1C - @ItemPositions) >> 2
	.db		(@Items_Sector3_Room1E - @ItemPositions) >> 2
	.db		(@Items_Sector3_Room21 - @ItemPositions) >> 2
	.db		(@Items_Sector3_Room22 - @ItemPositions) >> 2
	.db		(@Items_Sector3_Room23 - @ItemPositions) >> 2
	.db		(@Items_Sector3_Room25 - @ItemPositions) >> 2
	.db		(@Items_Sector4_Room06 - @ItemPositions) >> 2
.endautoregion

.autoregion
@@Items_Sector4:
	.db		06h, 0Ah, 0Dh, 0Fh, 11h, 17h, 18h, 1Ch
	.db		21h, 24h, 26h, 29h, 2Eh
	.fill	16 - (. - @@Items_Sector4), 0FFh
	.db		(@Items_Sector4_Room06 - @ItemPositions) >> 2
	.db		(@Items_Sector4_Room0A - @ItemPositions) >> 2
	.db		(@Items_Sector4_Room0D - @ItemPositions) >> 2
	.db		(@Items_Sector4_Room0F - @ItemPositions) >> 2
	.db		(@Items_Sector4_Room11 - @ItemPositions) >> 2
	.db		(@Items_Sector4_Room17 - @ItemPositions) >> 2
	.db		(@Items_Sector4_Room18 - @ItemPositions) >> 2
	.db		(@Items_Sector4_Room1C - @ItemPositions) >> 2
	.db		(@Items_Sector4_Room21 - @ItemPositions) >> 2
	.db		(@Items_Sector4_Room24 - @ItemPositions) >> 2
	.db		(@Items_Sector4_Room26 - @ItemPositions) >> 2
	.db		(@Items_Sector4_Room29 - @ItemPositions) >> 2
	.db		(@Items_Sector4_Room2E - @ItemPositions) >> 2
	.db		(@Items_Sector5_Room04 - @ItemPositions) >> 2
.endautoregion

.autoregion
@@Items_Sector5:
	.db		04h, 0Ch, 0Eh, 12h, 16h, 17h, 1Ah, 1Eh
	.db		21h, 22h, 24h, 2Fh, 32h, 33h
	.fill	16 - (. - @@Items_Sector5), 0FFh
	.db		(@Items_Sector5_Room04 - @ItemPositions) >> 2
	.db		(@Items_Sector5_Room0C - @ItemPositions) >> 2
	.db		(@Items_Sector5_Room0E - @ItemPositions) >> 2
	.db		(@Items_Sector5_Room12 - @ItemPositions) >> 2
	.db		(@Items_Sector5_Room16 - @ItemPositions) >> 2
	.db		(@Items_Sector5_Room17 - @ItemPositions) >> 2
	.db		(@Items_Sector5_Room1A - @ItemPositions) >> 2
	.db		(@Items_Sector5_Room1E - @ItemPositions) >> 2
	.db		(@Items_Sector5_Room21 - @ItemPositions) >> 2
	.db		(@Items_Sector5_Room22 - @ItemPositions) >> 2
	.db		(@Items_Sector5_Room24 - @ItemPositions) >> 2
	.db		(@Items_Sector5_Room2F - @ItemPositions) >> 2
	.db		(@Items_Sector5_Room32 - @ItemPositions) >> 2
	.db		(@Items_Sector5_Room33 - @ItemPositions) >> 2
	.db		(@Items_Sector6_Room00 - @ItemPositions) >> 2
.endautoregion

.autoregion
@@Items_Sector6:
	.db		00h, 0Fh, 12h, 18h, 1Ah, 1Eh, 22h, 26h
	.db		27h
	.fill	16 - (. - @@Items_Sector6), 0FFh
	.db		(@Items_Sector6_Room00 - @ItemPositions) >> 2
	.db		(@Items_Sector6_Room0F - @ItemPositions) >> 2
	.db		(@Items_Sector6_Room12 - @ItemPositions) >> 2
	.db		(@Items_Sector6_Room18 - @ItemPositions) >> 2
	.db		(@Items_Sector6_Room1A - @ItemPositions) >> 2
	.db		(@Items_Sector6_Room1E - @ItemPositions) >> 2
	.db		(@Items_Sector6_Room22 - @ItemPositions) >> 2
	.db		(@Items_Sector6_Room26 - @ItemPositions) >> 2
	.db		(@Items_Sector6_Room27 - @ItemPositions) >> 2
	.db		(@ItemPositions_End - @ItemPositions) >> 2
.endautoregion

.autoregion
.align 2
@ItemPositions:
@Items_MainDeck_Room07:
	.db		0Dh, 0Eh
	.db		Upgrade_MissileTank
	.skip 1
@Items_MainDeck_Room11:
	.db		09h, 14h
	.db		Upgrade_PowerBombTank
	.skip 1
@Items_MainDeck_Room23:
	.db		0Eh, 41h
	.db		Upgrade_MissileTank
	.skip 1
@Items_MainDeck_Room26:
	.db		35h, 0Ah
	.db		Upgrade_EnergyTank
	.skip 1
@Items_MainDeck_Room2D:
	.db		04h, 04h
	.db		Upgrade_MissileTank
	.skip 1
@Items_MainDeck_Room2F:
	.db		04h, 03h
	.db		Upgrade_PowerBombTank
	.skip 1
@Items_MainDeck_Room32:
	.db		36h, 08h
	.db		Upgrade_EnergyTank
	.skip 1
@Items_MainDeck_Room33:
	.db		05h, 1Dh
	.db		Upgrade_MissileTank
	.skip 1
@Items_MainDeck_Room39:
	.db		0Ch, 0Ah
	.db		Upgrade_PowerBombTank
	.skip 1
@Items_MainDeck_Room45:
	.db		1Dh, 1Dh
	.db		Upgrade_MissileTank
	.skip 1
@Items_MainDeck_Room48:
	.db		0Dh, 09h
	.db		Upgrade_MissileTank
	.skip 1
@Items_MainDeck_Room49:
	.db		06h, 0Ah
	.db		Upgrade_MissileTank
	.skip 1
@Items_MainDeck_Room54:
	.db		0Eh, 0Ah
	.db		Upgrade_EnergyTank
	.skip 1
@Items_Sector1_Room05:
	.db		1Bh, 0Ah
	.db		Upgrade_EnergyTank
	.skip 1
@Items_Sector1_Room11:
	.db		08h, 06h
	.db		Upgrade_MissileTank
	.skip 1
	.db		19h, 08h
	.db		Upgrade_MissileTank
	.skip 1
	.db		2Ch, 13h
	.db		Upgrade_MissileTank
	.skip 1
@Items_Sector1_Room1E:
	.db		0Fh, 08h
	.db		Upgrade_EnergyTank
	.skip 1
@Items_Sector1_Room27:
	.db		04h, 05h
	.db		Upgrade_PowerBombTank
	.skip 1
@Items_Sector1_Room28:
	.db		0Ch, 08h
	.db		Upgrade_EnergyTank
	.skip 1
@Items_Sector1_Room2B:
	.db		0Dh, 0Bh
	.db		Upgrade_MissileTank
	.skip 1
@Items_Sector1_Room2C:
	.db		04h, 08h
	.db		Upgrade_MissileTank
	.skip 1
@Items_Sector1_Room2F:
	.db		0Ah, 02h
	.db		Upgrade_PowerBombTank
	.skip 1
@Items_Sector1_Room32:
	.db		06h, 08h
	.db		Upgrade_MissileTank
	.skip 1
@Items_Sector1_Room34:
	.db		0Dh, 07h
	.db		Upgrade_PowerBombTank
	.skip 1
@Items_Sector2_Room06:
	.db		1Dh, 08h
	.db		Upgrade_MissileTank
	.skip 1
@Items_Sector2_Room09:
	.db		0Dh, 04h
	.db		Upgrade_MissileTank
	.skip 1
@Items_Sector2_Room0A:
	.db		13h, 23h
	.db		Upgrade_MissileTank
	.skip 1
@Items_Sector2_Room11:
	.db		2Ch, 07h
	.db		Upgrade_EnergyTank
	.skip 1
@Items_Sector2_Room15:
	.db		1Dh, 04h
	.db		Upgrade_EnergyTank
	.skip 1
@Items_Sector2_Room19:
	.db		04h, 08h
	.db		Upgrade_MissileTank
	.skip 1
@Items_Sector2_Room1B:
	.db		1Ch, 07h
	.db		Upgrade_MissileTank
	.skip 1
@Items_Sector2_Room1F:
	.db		28h, 07h
	.db		Upgrade_MissileTank
	.skip 1
@Items_Sector2_Room21:
	.db		15h, 08h
	.db		Upgrade_MissileTank
	.skip 1
@Items_Sector2_Room2A:
	.db		05h, 08h
	.db		Upgrade_MissileTank
	.skip 1
@Items_Sector2_Room2F:
	.db		1Dh, 10h
	.db		Upgrade_PowerBombTank
	.skip 1
@Items_Sector2_Room32:
	.db		03h, 07h
	.db		Upgrade_PowerBombTank
	.skip 1
	.db		03h, 18h
	.db		Upgrade_PowerBombTank
	.skip 1
@Items_Sector2_Room36:
	.db		04h, 05h
	.db		Upgrade_EnergyTank
	.skip 1
	.db		09h, 0Eh
	.db		Upgrade_PowerBombTank
	.skip 1
@Items_Sector2_Room37:
	.db		07h, 04h
	.db		Upgrade_PowerBombTank
	.skip 1
	.db		0Ah, 1Ah
	.db		Upgrade_MissileTank
	.skip 1
@Items_Sector3_Room03:
	.db		3Ch, 0Dh
	.db		Upgrade_MissileTank
	.skip 1
@Items_Sector3_Room06:
	.db		05h, 11h
	.db		Upgrade_MissileTank
	.skip 1
@Items_Sector3_Room08:
	.db		09h, 09h
	.db		Upgrade_PowerBombTank
	.skip 1
	.db		16h, 0Dh
	.db		Upgrade_EnergyTank
	.skip 1
@Items_Sector3_Room09:
	.db		2Ah, 08h
	.db		Upgrade_MissileTank
	.skip 1
@Items_Sector3_Room0C:
	.db		0Ch, 19h
	.db		Upgrade_PowerBombTank
	.skip 1
@Items_Sector3_Room13:
	.db		13h, 0Dh
	.db		Upgrade_MissileTank
	.skip 1
	.db		2Bh, 0Ah
	.db		Upgrade_EnergyTank
	.skip 1
@Items_Sector3_Room1C:
	.db		0Ch, 07h
	.db		Upgrade_EnergyTank
	.skip 1
	.db		24h, 1Bh
	.db		Upgrade_MissileTank
	.skip 1
@Items_Sector3_Room1E:
	.db		04h, 0Dh
	.db		Upgrade_PowerBombTank
	.skip 1
@Items_Sector3_Room21:
	.db		0Fh, 0Ah
	.db		Upgrade_MissileTank
	.skip 1
@Items_Sector3_Room22:
	.db		0Ah, 0Fh
	.db		Upgrade_MissileTank
	.skip 1
@Items_Sector3_Room23:
	.db		04h, 1Bh
	.db		Upgrade_PowerBombTank
	.skip 1
	.db		0Fh, 56h
	.db		Upgrade_PowerBombTank
	.skip 1
@Items_Sector3_Room25:
	.db		0Fh, 03h
	.db		Upgrade_PowerBombTank
	.skip 1
@Items_Sector4_Room06:
	.db		16h, 1Dh
	.db		Upgrade_PowerBombTank
	.skip 1
@Items_Sector4_Room0A:
	.db		0Ch, 1Dh
	.db		Upgrade_EnergyTank
	.skip 1
@Items_Sector4_Room0D:
	.db		18h, 09h
	.db		Upgrade_MissileTank
	.skip 1
	.db		26h, 0Fh
	.db		Upgrade_MissileTank
	.skip 1
@Items_Sector4_Room0F:
	.db		2Ch, 05h
	.db		Upgrade_MissileTank
	.skip 1
@Items_Sector4_Room11:
	.db		17h, 14h
	.db		Upgrade_MissileTank
	.skip 1
@Items_Sector4_Room17:
	.db		39h, 13h
	.db		Upgrade_PowerBombTank
	.skip 1
@Items_Sector4_Room18:
	.db		28h, 07h
	.db		Upgrade_PowerBombTank
	.skip 1
@Items_Sector4_Room1C:
	.db		09h, 06h
	.db		Upgrade_MissileTank
	.skip 1
@Items_Sector4_Room21:
	.db		0Ah, 0Dh
	.db		Upgrade_MissileTank
	.skip 1
@Items_Sector4_Room24:
	.db		03h, 07h
	.db		Upgrade_MissileTank
	.skip 1
@Items_Sector4_Room26:
	.db		16h, 0Ah
	.db		Upgrade_MissileTank
	.skip 1
	.db		2Ah, 05h
	.db		Upgrade_PowerBombTank
	.skip 1
@Items_Sector4_Room29:
	.db		0Fh, 04h
	.db		Upgrade_EnergyTank
	.skip 1
@Items_Sector4_Room2E:
	.db		04h, 0Ah
	.db		Upgrade_MissileTank
	.skip 1
@Items_Sector5_Room04:
	.db		05h, 05h
	.db		Upgrade_PowerBombTank
	.skip 1
	.db		14h, 08h
	.db		Upgrade_MissileTank
	.skip 1
@Items_Sector5_Room0C:
	.db		03h, 0Ah
	.db		Upgrade_EnergyTank
	.skip 1
@Items_Sector5_Room0E:
	.db		0Dh, 03h
	.db		Upgrade_EnergyTank
	.skip 1
@Items_Sector5_Room12:
	.db		03h, 03h
	.db		Upgrade_PowerBombTank
	.skip 1
@Items_Sector5_Room16:
	.db		03h, 30h
	.db		Upgrade_PowerBombTank
	.skip 1
@Items_Sector5_Room17:
	.db		0Eh, 06h
	.db		Upgrade_PowerBombTank
	.skip 1
@Items_Sector5_Room1A:
	.db		04h, 06h
	.db		Upgrade_PowerBombTank
	.skip 1
@Items_Sector5_Room1E:
	.db		17h, 07h
	.db		Upgrade_MissileTank
	.skip 1
@Items_Sector5_Room21:
	.db		0Eh, 03h
	.db		Upgrade_MissileTank
	.skip 1
@Items_Sector5_Room22:
	.db		0Eh, 08h
	.db		Upgrade_EnergyTank
	.skip 1
@Items_Sector5_Room24:
	.db		08h, 08h
	.db		Upgrade_PowerBombTank
	.skip 1
@Items_Sector5_Room2F:
	.db		04h, 0Ah
	.db		Upgrade_PowerBombTank
	.skip 1
@Items_Sector5_Room32:
	.db		0Dh, 08h
	.db		Upgrade_PowerBombTank
	.skip 1
@Items_Sector5_Room33:
	.db		0Bh, 03h
	.db		Upgrade_MissileTank
	.skip 1
@Items_Sector6_Room00:
	.db		29h, 12h
	.db		Upgrade_MissileTank
	.skip 1
@Items_Sector6_Room0F:
	.db		03h, 03h
	.db		Upgrade_MissileTank
	.skip 1
@Items_Sector6_Room12:
	.db		0Fh, 03h
	.db		Upgrade_PowerBombTank
	.skip 1
	.db		1Dh, 14h
	.db		Upgrade_MissileTank
	.skip 1
@Items_Sector6_Room18:
	.db		1Dh, 09h
	.db		Upgrade_MissileTank
	.skip 1
@Items_Sector6_Room1A:
	.db		05h, 06h
	.db		Upgrade_EnergyTank
	.skip 1
@Items_Sector6_Room1E:
	.db		09h, 0Dh
	.db		Upgrade_MissileTank
	.skip 1
	.db		13h, 08h
	.db		Upgrade_MissileTank
	.skip 1
@Items_Sector6_Room22:
	.db		0Eh, 08h
	.db		Upgrade_EnergyTank
	.skip 1
@Items_Sector6_Room26:
	.db		2Dh, 06h
	.db		Upgrade_EnergyTank
	.skip 1
@Items_Sector6_Room27:
	.db		0Ah, 18h
	.db		Upgrade_PowerBombTank
	.skip 1
	.db		21h, 0Ah
	.db		Upgrade_PowerBombTank
	.skip 1
@ItemPositions_End:
.endautoregion

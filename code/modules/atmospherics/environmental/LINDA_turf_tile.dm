/turf
	//conductivity is divided by 10 when interacting with air for balance purposes
	var/thermal_conductivity = 0.05
	var/heat_capacity = 1

	//list of open turfs adjacent to us
	var/list/atmos_adjacent_turfs
	//bitfield of dirs in which we thermal conductivity is blocked
	var/conductivity_blocked_directions = NONE

	//used for mapping and for breathing while in walls (because that's a thing that needs to be accounted for...)
	//string parsed by /datum/gas/proc/copy_from_turf
	var/initial_gas_mix = OPENTURF_DEFAULT_ATMOS
	//approximation of MOLES_O2STANDARD and MOLES_N2STANDARD pending byond allowing constant expressions to be embedded in constant strings
	// If someone will place 0 of some gas there, SHIT WILL BREAK. Do not do that.

/turf/open
	//used for spacewind
	var/pressure_difference = 0
	var/pressure_direction = 0
	var/turf/pressure_specific_target

	var/datum/gas_mixture/air

	var/obj/effect/hotspot/active_hotspot
	var/planetary_atmos = FALSE //air will revert to initial_gas_mix over time

	/// How much fuel this open turf provides to turf fires, and how easily they can be ignited in the first place. Can be negative to make fires die out faster.
	var/flammability = 0.3

	var/list/atmos_overlay_types //gas IDs of current active gas overlays

/turf/open/Initialize(mapload, inherited_virtual_z)
	air = new(2500,src)
	air.copy_from_turf(src)
	update_air_ref(planetary_atmos ? AIR_REF_PLANETARY_TURF : AIR_REF_OPEN_TURF)
	return ..()

/turf/open/Destroy()
	if(active_hotspot)
		QDEL_NULL(active_hotspot)
	return ..()

/////////////////GAS MIXTURE PROCS///////////////////

/turf/open/assume_air(datum/gas_mixture/giver) //use this for machines to adjust air
	return assume_air_ratio(giver, 1)

/turf/open/assume_air_moles(datum/gas_mixture/giver, moles)
	if(!giver)
		return FALSE
	giver.transfer_to(air, moles)
	return TRUE

/turf/open/assume_air_ratio(datum/gas_mixture/giver, ratio)
	if(!giver)
		return FALSE
	giver.transfer_ratio_to(air, ratio)
	return TRUE

/turf/open/transfer_air(datum/gas_mixture/taker, moles)
	if(!taker || !return_air()) // shouldn't transfer from space
		return FALSE
	air.transfer_to(taker, moles)
	return TRUE

/turf/open/transfer_air_ratio(datum/gas_mixture/taker, ratio)
	if(!taker || !return_air())
		return FALSE
	air.transfer_ratio_to(taker, ratio)
	return TRUE

/turf/open/remove_air(amount)
	var/datum/gas_mixture/ours = return_air()
	var/datum/gas_mixture/removed = ours.remove(amount)
	return removed

/turf/open/remove_air_ratio(ratio)
	var/datum/gas_mixture/ours = return_air()
	var/datum/gas_mixture/removed = ours.remove_ratio(ratio)
	return removed

/turf/open/proc/copy_air_with_tile(turf/open/T)
	if(istype(T))
		air.copy_from(T.air)

/turf/open/proc/copy_air(datum/gas_mixture/copy)
	if(copy)
		air.copy_from(copy)

/turf/return_air()
	RETURN_TYPE(/datum/gas_mixture)
	var/datum/gas_mixture/GM = new
	GM.copy_from_turf(src)
	return GM

/turf/open/return_air()
	RETURN_TYPE(/datum/gas_mixture)
	return air

/turf/open/return_analyzable_air()
	return return_air()

/turf/temperature_expose()
	if(return_temperature() > heat_capacity)
		to_be_destroyed = TRUE


/turf/open/proc/eg_reset_cooldowns()
/turf/open/proc/eg_garbage_collect()
/turf/open/proc/get_excited()
/turf/open/proc/set_excited()

/////////////////////////GAS OVERLAYS//////////////////////////////


/turf/open/proc/update_visuals()

	var/list/atmos_overlay_types = src.atmos_overlay_types // Cache for free performance
	var/list/new_overlay_types = list()
	var/static/list/nonoverlaying_gases = typecache_of_gases_with_no_overlays()

	if(!air) // 2019-05-14: was not able to get this path to fire in testing. Consider removing/looking at callers -Naksu
		if (atmos_overlay_types)
			for(var/overlay in atmos_overlay_types)
				vis_contents -= overlay
			src.atmos_overlay_types = null
		return


	for(var/id in air.get_gases())
		if (nonoverlaying_gases[id])
			continue
		var/gas_overlay = GLOB.gas_data.overlays[id]
		if(gas_overlay && air.get_moles(id) > GLOB.gas_data.visibility[id])
			new_overlay_types += gas_overlay[min(FACTOR_GAS_VISIBLE_MAX, CEILING(air.get_moles(id) / MOLES_GAS_VISIBLE_STEP, 1))]

	if (atmos_overlay_types)
		for(var/overlay in atmos_overlay_types-new_overlay_types) //doesn't remove overlays that would only be added
			vis_contents -= overlay

	if (length(new_overlay_types))
		if (atmos_overlay_types)
			vis_contents += new_overlay_types - atmos_overlay_types //don't add overlays that already exist
		else
			vis_contents += new_overlay_types

	UNSETEMPTY(new_overlay_types)
	src.atmos_overlay_types = new_overlay_types

/turf/open/proc/set_visuals(list/new_overlay_types)
	if (atmos_overlay_types)
		for(var/overlay in atmos_overlay_types-new_overlay_types) //doesn't remove overlays that would only be added
			vis_contents -= overlay

	if (length(new_overlay_types))
		if (atmos_overlay_types)
			vis_contents += new_overlay_types - atmos_overlay_types //don't add overlays that already exist
		else
			vis_contents += new_overlay_types
	UNSETEMPTY(new_overlay_types)
	src.atmos_overlay_types = new_overlay_types

/proc/typecache_of_gases_with_no_overlays()
	. = list()
	for (var/gastype in subtypesof(/datum/gas))
		var/datum/gas/gasvar = gastype
		if (!initial(gasvar.gas_overlay))
			.[initial(gasvar.id)] = TRUE

/////////////////////////////SIMULATION///////////////////////////////////

/turf/proc/process_cell(fire_count)
/turf/open/proc/equalize_pressure_in_zone(cyclenum)

/turf/proc/consider_firelocks(turf/T2) //TODO: Find out why this sometimes gets called. Possibly to do with atmos adjacency not being updated in auxmos?
/turf/open/consider_firelocks(turf/T2)
	if(blocks_air)
		return
	for(var/obj/machinery/airalarm/alarm in src)
		alarm.handle_decomp_alarm()
	for(var/obj/machinery/door/firedoor/FD in src)
		FD.emergency_pressure_stop()
	for(var/obj/machinery/door/firedoor/FD in T2)
		FD.emergency_pressure_stop()

/turf/proc/handle_decompression_floor_rip()

/turf/open/floor/handle_decompression_floor_rip(sum)
	if(!blocks_air && sum > 20 && prob(clamp(sum / 10, 0, 30)))
		remove_tile()

/turf/open/process_cell(fire_count)

//////////////////////////SPACEWIND/////////////////////////////

/turf/proc/consider_pressure_difference(turf/T, difference)
	return

/turf/open/consider_pressure_difference(turf/T, difference)
	SSair.high_pressure_delta |= src
	if(difference > pressure_difference)
		pressure_direction = get_dir(src, T)
		pressure_difference = difference

/turf/open/proc/high_pressure_movements()
	if(blocks_air)
		return
	var/multiplier = 1
	if(locate(/obj/structure/rack) in src)
		multiplier *= 0.1
	else if(locate(/obj/structure/table) in src)
		multiplier *= 0.2
	for(var/atom/movable/M as anything in src)
		if(!M.anchored && !M.pulledby && M.last_high_pressure_movement_air_cycle < SSair.times_fired && (M.flags_1 & INITIALIZED_1) && !QDELETED(M))
			M.experience_pressure_difference(pressure_difference * multiplier, pressure_direction, 0, pressure_specific_target)

	if(pressure_difference > 100)
		new /obj/effect/temp_visual/dir_setting/space_wind(src, pressure_direction, clamp(round(sqrt(pressure_difference) * 2), 10, 255))

/atom/movable/var/pressure_resistance = 10
/atom/movable/var/last_high_pressure_movement_air_cycle = 0

/atom/movable/proc/experience_pressure_difference(pressure_difference, direction, pressure_resistance_prob_delta = 0, throw_target)
	var/const/PROBABILITY_OFFSET = 40
	var/const/PROBABILITY_BASE_PRECENT = 10
	var/max_force = sqrt(pressure_difference)*(MOVE_FORCE_DEFAULT / 5)
	set waitfor = 0
	var/move_prob = 100
	if (pressure_resistance > 0)
		move_prob = (pressure_difference/pressure_resistance*PROBABILITY_BASE_PRECENT)-PROBABILITY_OFFSET
	move_prob += pressure_resistance_prob_delta
	if (move_prob > PROBABILITY_OFFSET && prob(move_prob) && (move_resist != INFINITY) && (!anchored && (max_force >= (move_resist * MOVE_FORCE_PUSH_RATIO))) || (anchored && (max_force >= (move_resist * MOVE_FORCE_FORCEPUSH_RATIO))))
		var/move_force = max_force * clamp(move_prob, 0, 100) / 100
		if(ismob(src))
			var/mob/M = src
			if(M.mob_negates_gravity())
				move_force = 0
		if(move_force > 6000)
			// WALLSLAM HELL TIME OH BOY
			var/turf/throw_turf = get_ranged_target_turf(get_turf(src), direction, round(move_force / 2000))
			if(throw_target && (get_dir(src, throw_target) & direction))
				throw_turf = get_turf(throw_target)
			var/throw_speed = clamp(round(move_force / 3000), 1, 10)
			throw_at(throw_turf, move_force / 3000, throw_speed, quickstart = FALSE)
		else if(move_force > 0)
			step(src, direction)
		last_high_pressure_movement_air_cycle = SSair.times_fired

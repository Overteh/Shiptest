/obj/machinery/portable_atmospherics
	name = "portable_atmospherics"
	icon = 'icons/obj/atmos.dmi'
	use_power = NO_POWER_USE
	max_integrity = 250
	armor = list("melee" = 0, "bullet" = 0, "laser" = 0, "energy" = 100, "bomb" = 0, "bio" = 100, "rad" = 100, "fire" = 60, "acid" = 30)
	anchored = FALSE
	interacts_with_air = TRUE

	var/datum/gas_mixture/air_contents
	var/obj/machinery/atmospherics/components/unary/portables_connector/connected_port
	var/obj/item/tank/holding

	var/volume = 0

	var/maximum_pressure = 90 * ONE_ATMOSPHERE

/obj/machinery/portable_atmospherics/Initialize(mapload)
	. = ..()
	air_contents = new(volume)
	air_contents.set_temperature(T20C)
	SSair.start_processing_machine(src, mapload)

/obj/machinery/portable_atmospherics/Destroy()
	disconnect()
	QDEL_NULL(air_contents)
	SSair.stop_processing_machine(src)

	return ..()

/obj/machinery/portable_atmospherics/ex_act(severity, target)
	if(severity == 1 || target == src)
		if(resistance_flags & INDESTRUCTIBLE)
			return //indestructible cans shouldn't release air

		//This explosion will destroy the can, release its air.
		var/turf/T = get_turf(src)
		T.assume_air(air_contents)
		T.air_update_turf()

	return ..()

/obj/machinery/portable_atmospherics/process_atmos(seconds_per_tick)
	if(!connected_port) // Pipe network handles reactions if connected.
		air_contents.react(src)

/obj/machinery/portable_atmospherics/return_air()
	return air_contents

/obj/machinery/portable_atmospherics/return_analyzable_air()
	return air_contents

/obj/machinery/portable_atmospherics/proc/connect(obj/machinery/atmospherics/components/unary/portables_connector/new_port)
	//Make sure not already connected to something else
	if(connected_port || !new_port || new_port.connected_device)
		return FALSE

	//Make sure are close enough for a valid connection
	if(new_port.loc != get_turf(src))
		return FALSE

	//Perform the connection
	connected_port = new_port
	connected_port.connected_device = src
	var/datum/pipeline/connected_port_parent = connected_port.parents[1]
	connected_port_parent.reconcile_air()

	anchored = TRUE //Prevent movement
	pixel_x = new_port.pixel_x
	pixel_y = new_port.pixel_y
	update_appearance()
	return TRUE

/obj/machinery/portable_atmospherics/Move()
	. = ..()
	if(.)
		disconnect()

/obj/machinery/portable_atmospherics/proc/disconnect()
	if(!connected_port)
		return FALSE
	anchored = FALSE
	connected_port.connected_device = null
	connected_port = null
	pixel_x = 0
	pixel_y = 0
	update_appearance()
	return TRUE

/obj/machinery/portable_atmospherics/AltClick(mob/living/user)
	. = ..()
	if(!istype(user) || !user.canUseTopic(src, BE_CLOSE, !ismonkey(user)) || !can_interact(user))
		return
	if(holding)
		to_chat(user, span_notice("You remove [holding] from [src]."))
		replace_tank(user, TRUE)

/obj/machinery/portable_atmospherics/examine(mob/user)
	. = ..()
	if(holding)
		. += span_notice("\The [src] contains [holding]. Alt-click [src] to remove it.")+\
			span_notice("Click [src] with another gas tank to hot swap [holding].")

/obj/machinery/portable_atmospherics/proc/replace_tank(mob/living/user, close_valve, obj/item/tank/new_tank)
	if(!user)
		return FALSE
	if(holding)
		user.put_in_hands(holding)
		holding = null
	if(new_tank)
		holding = new_tank
	update_appearance()
	return TRUE

/obj/machinery/portable_atmospherics/attackby(obj/item/W, mob/user, params)
	if(istype(W, /obj/item/tank))
		if(!(machine_stat & BROKEN))
			var/obj/item/tank/T = W
			if(!user.transferItemToLoc(T, src))
				return
			to_chat(user, span_notice("[holding ? "In one smooth motion you pop [holding] out of [src]'s connector and replace it with [T]" : "You insert [T] into [src]"]."))
			investigate_log("had its internal [holding] swapped with [T] by [key_name(user)].", INVESTIGATE_ATMOS)
			replace_tank(user, FALSE, T)
			update_appearance()
	else if(W.tool_behaviour == TOOL_WRENCH)
		if(!(machine_stat & BROKEN))
			if(connected_port)
				investigate_log("was disconnected from [connected_port] by [key_name(user)].", INVESTIGATE_ATMOS)
				disconnect()
				W.play_tool_sound(src)
				user.visible_message( \
					"[user] disconnects [src].", \
					span_notice("You unfasten [src] from the port."), \
					span_hear("You hear a ratchet."))
				update_appearance()
				return
			else
				var/obj/machinery/atmospherics/components/unary/portables_connector/possible_port = locate(/obj/machinery/atmospherics/components/unary/portables_connector) in loc
				if(!possible_port)
					to_chat(user, span_notice("Nothing happens."))
					return
				if(!connect(possible_port))
					to_chat(user, span_notice("[name] failed to connect to the port."))
					return
				W.play_tool_sound(src)
				user.visible_message( \
					"[user] connects [src].", \
					span_notice("You fasten [src] to the port."), \
					span_hear("You hear a ratchet."))
				update_appearance()
				investigate_log("was connected to [possible_port] by [key_name(user)].", INVESTIGATE_ATMOS)
	else
		return ..()

/obj/machinery/portable_atmospherics/attacked_by(obj/item/I, mob/user)
	if(I.force < 10 && !(machine_stat & BROKEN))
		take_damage(0)
	else
		investigate_log("was smacked with \a [I] by [key_name(user)].", INVESTIGATE_ATMOS)
		add_fingerprint(user)
		..()

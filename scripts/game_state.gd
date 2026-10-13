extends Node

const CAR_NAMES := ["SportsCar", "SportsCar2", "NormalCar1", "NormalCar2", "SUV", "Taxi", "Cop"]
var selected_car := 0


func selected_name() -> String:
	return CAR_NAMES[selected_car]


func selected_asset_path() -> String:
	return "res://assets/cars/%s.res" % selected_name()

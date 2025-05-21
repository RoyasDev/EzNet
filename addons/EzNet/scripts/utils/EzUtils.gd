class_name EzUtils

const EPSILON = 0.00001

static func compare_approx_float(f1 : float, f2 : float) -> bool:
	return abs(f1 - f2) <= EPSILON

static func compare_approx_vector2(v1 : Vector2, v2 : Vector2) -> bool:
	return abs(v1.x - v2.x) <= EPSILON && abs(v1.y - v2.y) < EPSILON

static func compare_approx_vector3(v1 : Vector3, v2 : Vector3) -> bool:
	return abs(v1.x - v2.x) <= EPSILON && abs(v1.y - v2.y) <= EPSILON && abs(v1.z - v2.z) <= EPSILON

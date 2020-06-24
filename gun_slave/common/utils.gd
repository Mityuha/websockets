extends Node

func is_bit_enabled(mask, index):
	return mask & (1 << index) != 0

func enable_bit(mask, index):
	return mask | (1 << index)

func disable_bit(mask, index):
	return mask & ~(1 << index)
	
func enable_bit_or_do_nothing(mask, index, enable):
	if enable:
		return enable_bit(mask, index)
	return mask
		
func int_from_bytes(byte1:int, byte0:int)->int:
	var res = byte1 << 8 | byte0 ;
	return res
	
func int_from_bytes2_array(bytes:Array)->int:
	return int_from_bytes(bytes[0], bytes[1
	])
	
func int_2_bytes(num:int, bytes_num=4)->PoolByteArray:
	var res:PoolByteArray = PoolByteArray();
	for i in range(0, bytes_num):
		res.append((num >> (8*i)) & 0xff)
	return res
	
func bytes_2_int(bytes: PoolByteArray, bytes_num=4)->int:
	var res:int = 0
	for i in range(0, bytes_num):
		res |= bytes[i] << (8 * i);
	return res

func encode_data(data)->PoolByteArray:
	return var2bytes(data)

func decode_data(data: PoolByteArray):
	return bytes2var(data)

func _log(msg):
	print(msg)
	
class LockGuard:
	var _mutex
	#var _from = "?"
	func _init(mutex):
		_mutex = mutex
		_mutex.lock()
#		var stack = get_stack()
#		if stack:
#			var frame = get_stack()[1]
#			_from = "%30s:%-4d" % [frame.source.get_file(), frame.line] 
#			print( _from, " acquired")
#		else:
#			print("acquired")
	func _notification(what):
		if what == NOTIFICATION_PREDELETE:
			#print(_from, " releasing")
			_mutex.unlock()



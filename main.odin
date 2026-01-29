package main

import win32 "core:sys/windows"
import "core:fmt"

global_running: bool
global_performance_frequency: f64

win32_get_wall_clock :: proc() ->u64{
	result: win32.LARGE_INTEGER
	win32.QueryPerformanceCounter(&result)
	return u64(result)
}

win32_get_seconds_elapsed :: proc(start, end: u64) -> f64
{
	result := f64(end - start) / global_performance_frequency
	return result;
}

window_proc :: proc "stdcall" (hwnd: win32.HWND, msg: win32.UINT, wparam: win32.WPARAM, lparam: win32.LPARAM) -> win32.LRESULT {
    switch(msg) {
	case win32.WM_DESTROY:
		win32.PostQuitMessage(0)
	}

    return win32.DefWindowProcW(hwnd, msg, wparam, lparam)
}

main :: proc(){

	performance_frequency_result: win32.LARGE_INTEGER
	win32.QueryPerformanceFrequency(&performance_frequency_result)
	global_performance_frequency = f64(performance_frequency_result)

	CLASS_NAME :: "software renderer"
	instance := win32.HINSTANCE(win32.GetModuleHandleW(nil))

	window_class := win32.WNDCLASSW {
		style = win32.CS_OWNDC,
		lpfnWndProc = window_proc,
		lpszClassName = CLASS_NAME,
		hInstance = instance,
		hCursor = win32.LoadCursorA(nil, win32.IDC_ARROW),
	}

	class_atom := win32.RegisterClassW(&window_class)
    assert(class_atom != 0, "Failed to register window class")

    window := win32.CreateWindowW(
		CLASS_NAME,
		win32.L("Software Renderer"),
		win32.WS_OVERLAPPEDWINDOW, //win32.WS_VISIBLE,
		win32.CW_USEDEFAULT, win32.CW_USEDEFAULT,
		1280, 720,
		nil, nil, instance, nil,
	)
	assert(window != nil, "Failed to create window")

	win32.ShowWindow(window, win32.SW_SHOWDEFAULT)

	global_running = true
	prev_counter := win32_get_wall_clock()


	accumulator: f64
	dt: f64

	TIME_STEP :: 2.0

	for global_running{
		message: win32.MSG
		for win32.PeekMessageW(&message, nil, 0, 0, win32.PM_REMOVE) {
			win32.TranslateMessage(&message)
			win32.DispatchMessageW(&message)
		}

		for accumulator += dt; accumulator >= TIME_STEP; accumulator -= TIME_STEP {
			fmt.println("tick")
		}

		next_counter := win32_get_wall_clock()
		dt = win32_get_seconds_elapsed(prev_counter, next_counter)
		prev_counter = next_counter

	}
}
package main

import win32 "core:sys/windows"

window_proc :: proc "stdcall" (hwnd: win32.HWND, msg: win32.UINT, wparam: win32.WPARAM, lparam: win32.LPARAM) -> win32.LRESULT {
    switch(msg) {
	case win32.WM_DESTROY:
		win32.PostQuitMessage(0)
	}

    return win32.DefWindowProcW(hwnd, msg, wparam, lparam)
}

main :: proc(){
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
		win32.WS_VISIBLE,
		win32.CW_USEDEFAULT, win32.CW_USEDEFAULT,
		1280, 720,
		nil, nil, instance, nil,
	)
	assert(window != nil, "Failed to create window")

    msg: win32.MSG
    for	win32.GetMessageW(&msg, nil, 0, 0) > 0 {
		win32.TranslateMessage(&msg)
		win32.DispatchMessageW(&msg)
	}
}
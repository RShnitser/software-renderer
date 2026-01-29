package main

import win32 "core:sys/windows"
import d3d11 "vendor:directx/d3d11"
import dxgi "vendor:directx/dxgi"
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
	
	dc := win32.GetDC(window)


	feature_levels := [?]d3d11.FEATURE_LEVEL{d3d11.FEATURE_LEVEL._11_1, d3d11.FEATURE_LEVEL._11_0}

	device: ^d3d11.IDevice
	device_context: ^d3d11.IDeviceContext
	hr := d3d11.CreateDevice(
		nil,
		.HARDWARE,
		nil,
		{.BGRA_SUPPORT, .DEBUG},
		&feature_levels[0],
		len(feature_levels),
		d3d11.SDK_VERSION,
		&device,
		nil,
		&device_context,
	)
	assert(win32.SUCCEEDED(hr))

	dxgi_device: ^dxgi.IDevice
	hr = device->QueryInterface(dxgi.IDevice_UUID, (^rawptr)(&dxgi_device))
	assert(win32.SUCCEEDED(hr))

	adapter: ^dxgi.IAdapter
	hr = dxgi_device->GetAdapter(&adapter)
	assert(win32.SUCCEEDED(hr))

	factory: ^dxgi.IFactory2
	hr = adapter->GetParent(dxgi.IFactory2_UUID, (^rawptr)(&factory))
	assert(win32.SUCCEEDED(hr))

	swapchain_desc := dxgi.SWAP_CHAIN_DESC1 {
		Width = 0,
		Height = 0,
		Format = .B8G8R8A8_UNORM_SRGB,
		Stereo = false,
		SampleDesc = {Count = 1, Quality = 0},
		BufferUsage = {.RENDER_TARGET_OUTPUT},
		BufferCount = 2,
		Scaling = .STRETCH,
		SwapEffect = .DISCARD,
		AlphaMode = .UNSPECIFIED,
		Flags = {.ALLOW_MODE_SWITCH},
	}

	swapchain: ^dxgi.ISwapChain1
	hr = factory->CreateSwapChainForHwnd(device, window, &swapchain_desc, nil, nil, &swapchain)
	assert(win32.SUCCEEDED(hr))

	framebuffer: ^d3d11.ITexture2D
	hr = swapchain->GetBuffer(0, d3d11.ITexture2D_UUID, (^rawptr)(&framebuffer))
	assert(win32.SUCCEEDED(hr))

	framebuffer_view: ^d3d11.IRenderTargetView
	hr = device->CreateRenderTargetView(framebuffer, nil, &framebuffer_view)
	assert(win32.SUCCEEDED(hr))

	rect: win32.RECT
	win32.GetClientRect(window, &rect)
	width: u32 = u32(rect.right - rect.left)
	height: u32 = u32(rect.bottom - rect.top)

	rasterizer_desc := d3d11.RASTERIZER_DESC {
		FillMode = .SOLID,
		CullMode = .BACK,
	}

	rasterizer_state: ^d3d11.IRasterizerState
	hr = device->CreateRasterizerState(&rasterizer_desc, &rasterizer_state)
	assert(win32.SUCCEEDED(hr))

	win32.ShowWindow(window, win32.SW_SHOWDEFAULT)


	global_running = true
	prev_counter := win32_get_wall_clock()


	accumulator: f64
	dt: f64

	TIME_STEP :: 2.0

	for global_running{
		message: win32.MSG
		for win32.PeekMessageW(&message, nil, 0, 0, win32.PM_REMOVE) {
			switch message.message {
			case win32.WM_QUIT:
				global_running = false
			case:
				win32.TranslateMessage(&message)
				win32.DispatchMessageW(&message)
			}
		}

		for accumulator += dt; accumulator >= TIME_STEP; accumulator -= TIME_STEP {
			fmt.println("tick")
		}

		device_context->ClearRenderTargetView(framebuffer_view, &[4]f32{1.0, 0.0, 1.0, 1.0})
		swapchain->Present(1, {})

		next_counter := win32_get_wall_clock()
		dt = win32_get_seconds_elapsed(prev_counter, next_counter)
		prev_counter = next_counter

	}
}
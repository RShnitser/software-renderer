package main

import win32 "core:sys/windows"
import d3d11 "vendor:directx/d3d11"
import d3d "vendor:directx/d3d_compiler"
import dxgi "vendor:directx/dxgi"
import xa2 "vendor:windows/XAudio2"
import "core:fmt"
import "core:mem"
import "base:runtime"

CREATE_DANGEROUS_WINDOW :: win32.WM_USER + 0x1337
DESTROY_DANGEROUS_WINDOW :: win32.WM_USER + 0x1338

global_main_thread_id: win32.DWORD
global_running: bool
global_performance_frequency: f64

adapter: ^dxgi.IAdapter
// framebuffer: ^d3d11.ITexture2D
framebuffer_view: ^d3d11.IRenderTargetView
device_context: ^d3d11.IDeviceContext
device: ^d3d11.IDevice
swapchain: ^dxgi.ISwapChain1

DirectX :: struct{
	adapter: ^dxgi.IAdapter,
	framebuffer_view: ^d3d11.IRenderTargetView,
	device_context: ^d3d11.IDeviceContext,
	device: ^d3d11.IDevice,
	swapchain: ^dxgi.ISwapChain1,
}


XAudio2 :: struct{
	xaudio2: ^xa2.IXAudio2,
	mastering_voice: ^xa2.IXAudio2MasteringVoice,
	source_voice: ^xa2.IXAudio2SourceVoice,

	buffer_1:  []u16,
	buffer_2:  []u16,
}

SoundBuffer :: struct{
	data : []u16,
}

TEXTURE_WIDTH :: 1920
TEXTURE_HEIGHT :: 1080

WindowParams :: struct {
    dwExStyle: win32.DWORD,
    lpClassName: win32.LPCWSTR,
    lpWindowName: win32.LPCWSTR,
    dwStyle: win32.DWORD,
    X, Y, nWidth, nHeight: i32,
    hWndParent: win32.HWND,
    hMenu: win32.HMENU,
    hInstance: win32.HINSTANCE,
    lpParam: win32.LPVOID,
};

Color :: struct #packed{
	R, G, B, A: u8
}

Pixel :: struct #raw_union{
	value: u32,
	color: Color,
}

// debug_messages :: proc(info_queue: ^d3d11.IInfoQueue) {
// 	message_count := info_queue->GetNumStoredMessages()

// 	for i: u64 = 0; i < message_count; i += 1 {
// 		message_length: uint = 0
// 		info_queue->GetMessage(i, nil, &message_length)

// 		message: ^d3d11.MESSAGE = new(d3d11.MESSAGE, context.temp_allocator)
// 		info_queue->GetMessage(i, message, &message_length)

// 		if message.ID == .LIVE_DEVICE {
// 			continue
// 		}

// 		fmt.printfln("==================")
// 		fmt.printfln("Message ID: ", message.ID)
// 		fmt.printfln("Category: ", message.Category)
// 		fmt.printfln("Severity: ", message.Severity)
// 		fmt.printfln("Description: ", message.pDescription)
// 		fmt.printfln("==================")
// 	}
// 	free_all(context.temp_allocator)
// }
// VoiceCallback :: struct {
	// // Called just before this voice's processing pass begins.
	// OnVoiceProcessingPassStart: proc "system" (this: ^xa2.IXAudio2VoiceCallback, BytesRequired: u32),

	// // Called just after this voice's processing pass ends.
	// OnVoiceProcessingPassEnd: proc "system" (this: ^xa2.IXAudio2VoiceCallback),

	// // Called when this voice has just finished playing a buffer stream (as marked with the END_OF_STREAM flag on the last buffer).
	// OnStreamEnd: proc "system" (this: ^xa2.IXAudio2VoiceCallback),

	// // Called when this voice is about to start processing a new buffer.
	// OnBufferStart: proc "system" (this: ^xa2.IXAudio2VoiceCallback, pBufferContext: rawptr),

	// // Called when this voice has just finished processing a buffer.
	// // The buffer can now be reused or destroyed.
	// OnBufferEnd: proc "system" (this: ^xa2.IXAudio2VoiceCallback, pBufferContext: rawptr),

	// // Called when this voice has just reached the end position of a loop.
	// OnLoopEnd: proc "system" (this: ^xa2.IXAudio2VoiceCallback, pBufferContext: rawptr),

	// // Called in the event of a critical error during voice processing, such as a failing xAPO or an error from the hardware XMA decoder.
	// // The voice may have to be destroyed and re-created to recover from the error.
	// // The callback arguments report which buffer was being processed when the error occurred, and its HRESULT code.
	// OnVoiceError: proc "system" (this: ^xa2.IXAudio2VoiceCallback, pBufferContext: rawptr, Error: win32.HRESULT),
// }
// OnVoiceProcessingPassStart :: proc "system" (this: ^VoiceCallback, BytesRequired: u32){}
// OnVoiceProcessingPassEnd :: proc "system" (this: ^VoiceCallback){}
// OnStreamEnd :: proc "system" (this: ^VoiceCallback){}
// OnBufferStart :: proc "system" (this: ^VoiceCallback, pBufferContext: rawptr){}
// OnBufferEnd :: proc "system" (this: ^VoiceCallback, pBufferContext: rawptr){}
// OnLoopEnd :: proc "system" (this: ^VoiceCallback, pBufferContext: rawptr){}
// OnVoiceError :: proc "system" (this: ^VoiceCallback, pBufferContext: rawptr, Error: win32.HRESULT){}


write_audio_buffer :: proc(xaudio: ^XAudio2){

}


update_pixels :: proc(pixels: []Pixel){
	index : u32
	for h in 0..< TEXTURE_HEIGHT{
		for w in 0..< TEXTURE_WIDTH{
			pixels[index].color.G = u8(w)
			pixels[index].color.B = u8(h)
			index += 1
		}
	}
}

win32_get_wall_clock :: proc() ->u64{
	result: win32.LARGE_INTEGER
	win32.QueryPerformanceCounter(&result)
	return u64(result)
}

win32_get_seconds_elapsed :: proc(start, end: u64) -> f64{
	result := f64(end - start) / global_performance_frequency
	return result;
}

window_proc :: proc "stdcall" (hwnd: win32.HWND, msg: win32.UINT, wparam: win32.WPARAM, lparam: win32.LPARAM) -> win32.LRESULT {
	context = runtime.default_context()
    switch(msg) {
	case win32.WM_DESTROY:
		win32.PostQuitMessage(0)
	case win32.WM_SIZE:
		width := win32.LOWORD(lparam)
		height := win32.HIWORD(lparam)
		// if false{
		if swapchain != nil && device_context != nil && (width != 0 || height !=0 || wparam != win32.SIZE_MINIMIZED) {
		// if width > 0 && height > 0 && device_context != nil && framebuffer != nil && swapchain != nil && framebuffer_view != nil{

			
			// device_context->Flush()
			if framebuffer_view != nil{
				hr := framebuffer_view->Release()
				assert(win32.SUCCEEDED(hr))
				framebuffer_view = nil
			}

			//device_context->OMSetRenderTargets(0, nil, nil)
			// framebuffer->Release()
			// swapchain->Release()
			
			hr := swapchain->ResizeBuffers(0, u32(width), u32(height), .UNKNOWN, nil)
			assert(win32.SUCCEEDED(hr))

			framebuffer: ^d3d11.ITexture2D
			hr = swapchain->GetBuffer(0, d3d11.ITexture2D_UUID, (^rawptr)(&framebuffer))
			assert(win32.SUCCEEDED(hr))
			
			device->CreateRenderTargetView(framebuffer, nil, &framebuffer_view)
			framebuffer->Release()
			

			viewport := d3d11.VIEWPORT{0, 0, f32(width), f32(height), 0, 1}
			device_context->RSSetViewports(1, &viewport)


			// swapchain_desc := dxgi.SWAP_CHAIN_DESC1 {
			// 	Width = u32(width),
			// 	Height = u32(height),
			// 	Format = .B8G8R8A8_UNORM_SRGB,
			// 	Stereo = false,
			// 	SampleDesc = {Count = 1, Quality = 0},
			// 	BufferUsage = {.RENDER_TARGET_OUTPUT},
			// 	BufferCount = 2,
			// 	Scaling = .STRETCH,
			// 	SwapEffect = .DISCARD,
			// 	AlphaMode = .UNSPECIFIED,
			// 	Flags = {.ALLOW_MODE_SWITCH},
			// }
			// factory: ^dxgi.IFactory2
			// adapter->GetParent(dxgi.IFactory2_UUID, (^rawptr)(&factory))
			// factory->CreateSwapChainForHwnd(device, hwnd, &swapchain_desc, nil, nil, &swapchain)
		}
		return 0
	}

    return win32.DefWindowProcW(hwnd, msg, wparam, lparam)
}

// buffer_end_callback :: proc "system" (this: ^xa2.IXAudio2VoiceCallback, pBufferContext: rawptr){
// 		// event: win32.HANDLE = (win32.HANDLE)(pBufferContext)
// 		// win32.SetEvent(event)
// }


// main :: proc(){
main_thread :: proc "stdcall" (param : win32.LPVOID) -> win32.DWORD{

	service_window := (win32.HWND)(param)

	context = runtime.default_context()
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

    // window := win32.CreateWindowW(
	// 	CLASS_NAME,
	// 	win32.L("Software Renderer"),
	// 	win32.WS_OVERLAPPEDWINDOW, //win32.WS_VISIBLE,
	// 	win32.CW_USEDEFAULT, win32.CW_USEDEFAULT,
	// 	1280, 720,
	// 	nil, nil, instance, nil,
	// )
	win_params := WindowParams{
		0,
		CLASS_NAME,
		win32.L("Software Renderer"),
		win32.WS_OVERLAPPEDWINDOW,
		win32.CW_USEDEFAULT, win32.CW_USEDEFAULT,
		1280, 720,
		nil, nil, instance, nil,
	}
	window := cast(win32.HWND)cast(uintptr)(win32.SendMessageW(service_window, CREATE_DANGEROUS_WINDOW, uintptr(&win_params), 0))
	assert(window != nil, "Failed to create window")
	
	dc := win32.GetDC(window)



	pixels := make([]Pixel, TEXTURE_WIDTH * TEXTURE_HEIGHT)
	update_pixels(pixels)

	feature_levels := [?]d3d11.FEATURE_LEVEL{d3d11.FEATURE_LEVEL._11_1, d3d11.FEATURE_LEVEL._11_0}

	// device: ^d3d11.IDevice
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

	debug: ^d3d11.IDebug
	device->QueryInterface(d3d11.IDebug_UUID, (^rawptr)(&debug))

	debugInfoQueue: ^d3d11.IInfoQueue

	debug->QueryInterface(d3d11.IInfoQueue_UUID, (^rawptr)(&debugInfoQueue))
	debugInfoQueue->SetBreakOnSeverity(.CORRUPTION, true)
	debugInfoQueue->SetBreakOnSeverity(.ERROR, true)

	swapchain_desc := dxgi.SWAP_CHAIN_DESC1 {
		Width = 0,
		Height = 0,
		Format = .B8G8R8A8_UNORM,
		Stereo = false,
		SampleDesc = {Count = 1, Quality = 0},
		BufferUsage = {.RENDER_TARGET_OUTPUT},
		BufferCount = 2,
		Scaling = .STRETCH,
		SwapEffect = .FLIP_DISCARD,
		AlphaMode = .UNSPECIFIED,
		Flags = {.ALLOW_MODE_SWITCH},
	}

	// d3d11.CreateDeviceAndSwapchain(

	// )

	dxgi_device: ^dxgi.IDevice
	hr = device->QueryInterface(dxgi.IDevice_UUID, (^rawptr)(&dxgi_device))
	assert(win32.SUCCEEDED(hr))

	// adapter: ^dxgi.IAdapter
	hr = dxgi_device->GetAdapter(&adapter)
	assert(win32.SUCCEEDED(hr))

	factory: ^dxgi.IFactory2
	hr = adapter->GetParent(dxgi.IFactory2_UUID, (^rawptr)(&factory))
	assert(win32.SUCCEEDED(hr))



	// swapchain: ^dxgi.ISwapChain1
	hr = factory->CreateSwapChainForHwnd(device, window, &swapchain_desc, nil, nil, &swapchain)
	assert(win32.SUCCEEDED(hr))

	framebuffer: ^d3d11.ITexture2D
	hr = swapchain->GetBuffer(0, d3d11.ITexture2D_UUID, (^rawptr)(&framebuffer))
	assert(win32.SUCCEEDED(hr))

	// framebuffer_view: ^d3d11.IRenderTargetView
	hr = device->CreateRenderTargetView(framebuffer, nil, &framebuffer_view)
	assert(win32.SUCCEEDED(hr))
	framebuffer->Release()

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

	err_blob: ^d3d11.IBlob
	vs_blob: ^d3d11.IBlob
	hr = d3d.Compile(
		raw_data(shader),
		len(shader),
		"shaders.hlsl",
		nil,
		nil,
		"vs_main",
		"vs_5_0",
		0,
		0,
		&vs_blob,
		&err_blob,
	)
	if err_blob != nil{
		fmt.println(cstring(err_blob->GetBufferPointer()))
		err_blob->Release()
	}
	assert(win32.SUCCEEDED(hr))

	ps_blob: ^d3d11.IBlob
	hr = d3d.Compile(
		raw_data(shader),
		len(shader),
		"shaders.hlsl",
		nil,
		nil,
		"ps_main",
		"ps_5_0",
		0,
		0,
		&ps_blob,
		nil,
	)
	assert(win32.SUCCEEDED(hr))

	vertex_shader: ^d3d11.IVertexShader
	hr =
	device->CreateVertexShader(
		vs_blob->GetBufferPointer(),
		vs_blob->GetBufferSize(),
		nil,
		&vertex_shader,
	)
	assert(win32.SUCCEEDED(hr))

	pixel_shader: ^d3d11.IPixelShader
	hr =
	device->CreatePixelShader(
		ps_blob->GetBufferPointer(),
		ps_blob->GetBufferSize(),
		nil,
		&pixel_shader,
	)
	assert(win32.SUCCEEDED(hr))


	texture_desc := d3d11.TEXTURE2D_DESC{
		Width      = TEXTURE_WIDTH,
		Height     = TEXTURE_HEIGHT,
		MipLevels  = 1,
		ArraySize  = 1,
		Format     = .R8G8B8A8_UNORM_SRGB,
		SampleDesc = {Count = 1},
		Usage      = .DYNAMIC,
		BindFlags  = {.SHADER_RESOURCE},
		CPUAccessFlags = {.WRITE}
	}

	// texture_data := d3d11.SUBRESOURCE_DATA{
	// 	pSysMem     = raw_data(pixels),
	// 	SysMemPitch = TEXTURE_WIDTH * 4,
	// }

	texture: ^d3d11.ITexture2D
	device->CreateTexture2D(&texture_desc, nil, &texture)

	texture_view: ^d3d11.IShaderResourceView
	device->CreateShaderResourceView(texture, nil, &texture_view)

	sampler_desc := d3d11.SAMPLER_DESC{
			Filter         = .MIN_MAG_MIP_POINT,
			AddressU       = .CLAMP,
			AddressV       = .CLAMP,
			AddressW       = .CLAMP,
			ComparisonFunc = .NEVER,
		}
	sampler_state: ^d3d11.ISamplerState
	device->CreateSamplerState(&sampler_desc, &sampler_state)

	// hr = win32.CoInitializeEx(nil, .MULTITHREADED)
	hr = win32.CoInitializeEx(nil, .APARTMENTTHREADED)
	// defer win32.CoUninitialize()
	
	assert(hr == win32.S_OK, "Failed to initialize COM")

    xaudio2: ^xa2.IXAudio2
    if hr = xa2.Create(&xaudio2); hr != win32.S_OK {
        fmt.printfln("hr: %v", hr)
        err := win32.GetLastError()
        fmt.printfln("GetLastError: %8x (%v)", err, err)
		// return 1
        win32.ExitProcess(1)
    } 

	master_voice: ^xa2.IXAudio2MasteringVoice
	if hr = xaudio2->CreateMasteringVoice(&master_voice); hr != win32.S_OK {
        fmt.printfln("hr: %v", hr)
        err := win32.GetLastError()
        fmt.printfln("GetLastError: %8x (%v)", err, err)
        // return 1
		win32.ExitProcess(1)
    } 

	SAMPLES_PER_SECOND :: 48000
	BUFFER_SIZE :: mem.Megabyte * 8

	wave_format : win32.WAVEFORMATEX
	wave_format.wFormatTag = win32.WAVE_FORMAT_PCM
	wave_format.nChannels = 2
	wave_format.nSamplesPerSec = SAMPLES_PER_SECOND
	wave_format.wBitsPerSample = 16
	wave_format.nBlockAlign = (wave_format.nChannels * wave_format.wBitsPerSample) / 8
	wave_format.nAvgBytesPerSec = wave_format.nSamplesPerSec * u32(wave_format.nBlockAlign)
	wave_format.cbSize = 0

	callback: xa2.IXAudio2VoiceCallback
	// callback: VoiceCallback
	// callback.OnBufferEnd = buffer_end_callback
	callback.OnBufferEnd = proc "system" (this: ^xa2.IXAudio2VoiceCallback, pBufferContext: rawptr){
	// 	event: win32.HANDLE = (win32.HANDLE)(pBufferContext)
	// 	win32.SetEvent(event)
	}
	// callback.OnVoiceProcessingPassStart = proc "system" (this: ^xa2.IXAudio2VoiceCallback, BytesRequired: u32){}
	// callback.OnVoiceProcessingPassEnd = proc "system" (this: ^xa2.IXAudio2VoiceCallback){}
	// callback.OnStreamEnd = proc "system" (this: ^xa2.IXAudio2VoiceCallback){}
	// callback.OnBufferStart = proc "system" (this: ^xa2.IXAudio2VoiceCallback, pBufferContext: rawptr){}
	// callback.OnBufferEnd = proc "system" (this: ^xa2.IXAudio2VoiceCallback, pBufferContext: rawptr){}
	// callback.OnLoopEnd = proc "system" (this: ^xa2.IXAudio2VoiceCallback, pBufferContext: rawptr){}
	// callback.OnVoiceError = proc "system" (this: ^xa2.IXAudio2VoiceCallback, pBufferContext: rawptr, Error: win32.HRESULT){}

	source_voice: ^xa2.IXAudio2SourceVoice
	// if hr = xaudio2->CreateSourceVoice(&source_voice, &wave_format); hr != win32.S_OK {
	if hr = xaudio2->CreateSourceVoice(&source_voice, &wave_format, {}, xa2.DEFAULT_FREQ_RATIO, &callback, nil, nil); hr != win32.S_OK {
	// if hr = xaudio2->CreateSourceVoice(&source_voice, &wave_format, {}, xa2.DEFAULT_FREQ_RATIO, (^xa2.IXAudio2VoiceCallback)(&callback), nil, nil); hr != win32.S_OK {
        fmt.printfln("hr: %v", hr)
        err := win32.GetLastError()
        fmt.printfln("GetLastError: %8x (%v)", err, err)
        // return 1
		win32.ExitProcess(1)
    }

	xaudio2->StartEngine()
	source_voice->Start({})

	AUDIO_BUFFER_SIZE :: 1024 * 8
	buffers := [2][]u16{make([]u16, AUDIO_BUFFER_SIZE), make([]u16, AUDIO_BUFFER_SIZE)}
	events := [2]win32.HANDLE{win32.CreateEventW(nil, false, true, nil), win32.CreateEventW(nil, false, true, nil)}

	win32.ShowWindow(window, win32.SW_SHOWDEFAULT)


	global_running = true
	prev_counter := win32_get_wall_clock()


	accumulator: f64
	dt: f64

	TIME_STEP :: 0.5

	viewport := d3d11.VIEWPORT{0, 0, f32(width), f32(height), 0, 1}
	device_context->RSSetViewports(1, &viewport)

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

			for i in 0..<2{
				buffer := buffers[i]
				event := events[i]
				win32.WaitForSingleObject(event, win32.INFINITE)

				buffer_descriptor: xa2.BUFFER
				buffer_descriptor.pAudioData = raw_data(transmute([]u8)buffer)
				buffer_descriptor.AudioBytes = size_of(u16) * AUDIO_BUFFER_SIZE
				buffer_descriptor.pContext = event
				source_voice->SubmitSourceBuffer(&buffer_descriptor, nil)
			}
		}

		// win32.GetClientRect(window, &rect)
		// width: u32 = u32(rect.right - rect.left)
		// height: u32 = u32(rect.bottom - rect.top)
		// fmt.println(width, height)

		mapped_data: d3d11.MAPPED_SUBRESOURCE
		hr = device_context->Map(texture, 0, .WRITE_DISCARD, {}, &mapped_data)
		assert(win32.SUCCEEDED(hr))
		// update_pixels(pixels)
		mem.copy(mapped_data.pData, raw_data(pixels), TEXTURE_WIDTH * TEXTURE_HEIGHT * 4)
		device_context->Unmap(texture, 0)

		// viewport := d3d11.VIEWPORT{0, 0, f32(width), f32(height), 0, 1}
		device_context->ClearRenderTargetView(framebuffer_view, &[4]f32{1.0, 0.0, 1.0, 1.0})

		device_context->IASetPrimitiveTopology(.TRIANGLELIST)
		device_context->IASetInputLayout(nil)

		device_context->VSSetShader(vertex_shader, nil, 0)

		// device_context->RSSetViewports(1, &viewport)
		device_context->RSSetState(rasterizer_state)

		device_context->PSSetShader(pixel_shader, nil, 0)
		device_context->PSSetShaderResources(0, 1, &texture_view)
		device_context->PSSetSamplers(0, 1, &sampler_state)

		device_context->OMSetRenderTargets(1, &framebuffer_view, nil)
		device_context->OMSetBlendState(nil, nil, u32(d3d11.COLOR_WRITE_ENABLE_ALL))

		device_context->Draw(3, 0)

		swapchain->Present(1, {})

		next_counter := win32_get_wall_clock()
		dt = win32_get_seconds_elapsed(prev_counter, next_counter)
		// fmt.println(dt)
		prev_counter = next_counter

	}
	win32.CoUninitialize()
	win32.ExitProcess(0)
	// return 0
}

shader := `
struct vs_out {
	float4 position : SV_POSITION;
	float2 texcoord : TEX;
};
Texture2D    tex : register(t0);
SamplerState samp : register(s0);
vs_out vs_main(uint vI : SV_VertexId) {
	vs_out output;
	float2 texcoord = float2((vI << 1) & 2, vI & 2);
    output.texcoord = texcoord;
    output.position = float4(texcoord.x * 2 - 1, -texcoord.y * 2 + 1, 0, 1);
	return output;
}
float4 ps_main(vs_out input) : SV_TARGET {
	return tex.Sample(samp, input.texcoord);
}
`

service_window_proc :: proc "stdcall" (hwnd: win32.HWND, msg: win32.UINT, wparam: win32.WPARAM, lparam: win32.LPARAM) -> win32.LRESULT {

	result: win32.LRESULT = 0
    switch(msg) {
	case CREATE_DANGEROUS_WINDOW:
		window_params := (^WindowParams)(wparam)
		result = cast(win32.LRESULT)cast(uintptr)win32.CreateWindowExW(
			window_params.dwExStyle,
			window_params.lpClassName,
			window_params.lpWindowName,
			window_params.dwStyle,
			window_params.X,
			window_params.Y,
			window_params.nWidth,
			window_params.nHeight,
			window_params.hWndParent,
			window_params.hMenu,
			window_params.hInstance,
			window_params.lpParam,
		)

	case:
		result = win32.DefWindowProcW(hwnd, msg, wparam, lparam)
	}
	return result
}


main :: proc(){
	instance := win32.HINSTANCE(win32.GetModuleHandleW(nil))

	CLASS_NAME :: "service window"

	window_class := win32.WNDCLASSW {
		style = win32.CS_OWNDC,
		lpfnWndProc = service_window_proc,
		lpszClassName = CLASS_NAME,
		hInstance = instance,
		hCursor = win32.LoadCursorA(nil, win32.IDC_ARROW),
	}

	class_atom := win32.RegisterClassW(&window_class)
    assert(class_atom != 0, "Failed to register window class")

    window := win32.CreateWindowW(
		CLASS_NAME,
		win32.L("Service Window"),
		win32.WS_OVERLAPPEDWINDOW, //win32.WS_VISIBLE,
		win32.CW_USEDEFAULT, win32.CW_USEDEFAULT,
		win32.CW_USEDEFAULT, win32.CW_USEDEFAULT,
		nil, nil, instance, nil,
	)
	assert(window != nil, "Failed to create window")

	win32.CreateThread(nil, 0, main_thread, window, 0, &global_main_thread_id)

	for {
        message: win32.MSG
        win32.GetMessageW(&message, nil, 0, 0)
        win32.TranslateMessage(&message)
        if (message.message == win32.WM_CHAR) ||
           (message.message == win32.WM_KEYDOWN) ||
           (message.message == win32.WM_QUIT) ||
           (message.message == win32.WM_SIZE){
            win32.PostThreadMessageW(global_main_thread_id, message.message, message.wParam, message.lParam)
        }
        else{
            win32.DispatchMessageW(&message)
        }
    }
}
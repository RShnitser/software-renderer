package main

import win32 "core:/sys/windows"
import "base:runtime"
import "core:math"
import "core:fmt"
import "core:mem"
import "core:sync"
import ws "wasapi"

WinAudio :: struct{
    client: ^ws.IAudioClient,
    render_client: ^ws.IAudioRenderClient,

    stop: bool,
    lock: win32.SRWLOCK,
    thread: win32.HANDLE,
    event: win32.HANDLE,

    view1: rawptr,
    view2: rawptr,
}


audio_init :: proc(audio: ^WinAudio){
    hr_check(win32.CoInitializeEx(nil, .APARTMENTTHREADED))

    enumerator :^ws.IMMDeviceEnumerator
    hr_check(win32.CoCreateInstance(
        &ws.CLSID_MMDeviceEnumerator,
        nil,
        ws.CLSCTX_ALL,
        ws.IMMDeviceEnumerator_UUID,
        (^win32.LPVOID)(&enumerator),
    ))
    defer enumerator->Release()

    device: ^ws.IMMDevice
	hr_check(enumerator->GetDefaultAudioEndpoint(.eRender, .eConsole, &device))
    defer device->Release()

    hr_check(device->Activate(
        ws.IAudioClient_UUID, 
        ws.CLSCTX_ALL, 
        nil, 
        (^win32.LPVOID)(&audio.client),
    ))

    duration : ws.REFERENCE_TIME
    hr_check(audio.client->GetDevicePeriod(&duration, nil))

    format: win32.WAVEFORMATEX
	format.wFormatTag = win32.WAVE_FORMAT_PCM
	format.nChannels = 2
	format.nSamplesPerSec = 44100
	format.wBitsPerSample = 16
	format.nBlockAlign = (format.nChannels * format.wBitsPerSample) / 8
	format.nAvgBytesPerSec = format.nSamplesPerSec * u32(format.nBlockAlign)

    flags := ws.Audio_Client_Stream_Flags{.Event_Callback, .Auto_Convert_PCM, .Source_Default_Quality}

    hr_check(audio.client->Initialize(.SHARED, flags, duration, 0, &format, nil))

    hr_check(audio.client->GetService(ws.IAudioRenderClient_UUID, (^win32.LPVOID)(&audio.render_client)))

    audio.event = win32.CreateEventW(nil, false, false, nil)
    hr_check(audio.client->SetEventHandle(audio.event))

    RINGBUFFER_SIZE :: 1024 * 64
    placeholder1 := cast(^u8)win32.VirtualAlloc2(nil, nil, 2 * RINGBUFFER_SIZE, win32.MEM_RESERVE | win32.MEM_RESERVE_PLACEHOLDER, win32.PAGE_NOACCESS, nil, 0)
    placeholder2 := mem.ptr_offset(placeholder1, RINGBUFFER_SIZE)
    assert(placeholder1 != nil)

    ok := win32.VirtualFree(placeholder1, RINGBUFFER_SIZE, win32.MEM_RELEASE | win32.MEM_PRESERVE_PLACEHOLDER)
    assert(ok == true)
    
    section := win32.CreateFileMappingW(win32.INVALID_HANDLE_VALUE, nil, win32.PAGE_READWRITE, 0, RINGBUFFER_SIZE, nil)
    assert(section != nil)

    audio.view1 = win32.MapViewOfFile3(section, nil, placeholder1, 0, RINGBUFFER_SIZE, win32.MEM_REPLACE_PLACEHOLDER, win32.PAGE_READWRITE, nil, 0)
	audio.view2 = win32.MapViewOfFile3(section, nil, placeholder2, 0, RINGBUFFER_SIZE, win32.MEM_REPLACE_PLACEHOLDER, win32.PAGE_READWRITE, nil, 0)
	assert(audio.view1 != nil && audio.view2 != nil)

    audio.thread = win32.CreateThread(nil, 0, audio_thread, audio, 0, nil)

    win32.VirtualFree(placeholder1, 0, win32.MEM_RELEASE)
	win32.VirtualFree(placeholder2, 0, win32.MEM_RELEASE)
	win32.CloseHandle(section)

    sync.atomic_exchange(&audio.stop, false)

	win32.InitializeSRWLock(&audio.lock)
}

audio_thread :: proc "std" (param: win32.LPVOID) -> win32.DWORD{
    context = runtime.default_context()

    audio := (^WinAudio)(param)

   
    buffer_frame_count: u32
    hr_check(audio.client->GetBufferSize(&buffer_frame_count))
    hr_check(audio.client->Start())

   

    for !audio.stop{
        win32.WaitForSingleObject(audio.event, win32.INFINITE)

        padding_frame_count: u32
	    hr_check(audio.client->GetCurrentPadding(&padding_frame_count)) 

        max_output_frames := buffer_frame_count - padding_frame_count
        data: ^u8
	    hr_check(audio.render_client->GetBuffer(max_output_frames, &data))

        win32.AcquireSRWLockExclusive(&audio.lock)


        @(static) t_sine: f32
        tone_volume: f32 = 300
		wave_period: f32 = 44100 / 500

		sample_out :[^]i16 = ([^]i16)(data)
        buffer_index := 0
		for frame_index : u32 = 0; frame_index < max_output_frames; frame_index += 1{
			sine_value := math.sin(t_sine)
            // fmt.println(sine_value)
			sample_value := i16(sine_value * tone_volume)
  
            sample_out[buffer_index] = sample_value
            buffer_index += 1
            sample_out[buffer_index] = sample_value
            buffer_index += 1

			t_sine += 2.0*math.PI*1.0 / wave_period
			if t_sine > 2.0*math.PI{
				t_sine -= 2.0*math.PI
			}
		}
      
        hr_check(audio.render_client->ReleaseBuffer(max_output_frames, nil))
    }

    hr_check(audio.client->Stop())
    return 0
}

audio_shutdown :: proc(audio: ^WinAudio){
    sync.atomic_exchange(&audio.stop, true)
	win32.SetEvent(audio.event)

    win32.WaitForSingleObject(audio.thread, win32.INFINITE)

    win32.CloseHandle(audio.event)
    win32.CloseHandle(audio.thread)
    
    win32.UnmapViewOfFileEx(audio.view1, 0)
	win32.UnmapViewOfFileEx(audio.view2, 0)

    audio.client->Release()
    audio.render_client->Release()

    win32.CoUninitialize()
}
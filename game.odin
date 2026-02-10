package main

import "core:math"
import "core:fmt"

Color :: struct #packed{
	R, G, B, A: u8
}

Pixel :: struct #raw_union{
	value: u32,
	color: Color,
}

SoundBuffer :: struct{
    channels: i32,
    samples_per_second: i32,
	data : []u16,
}

GameState :: struct{
    audio_t_sine: f32,
    sine_wave :f32,
    volume: f32,
    delta_time: f32,
}

Button :: struct{
    has_changed: b32,
    is_down: b32,
}

Input :: struct{
    up: Button,
    down: Button,
}

process_input :: proc(button: ^Button, is_down: b32) {
	if button.is_down != is_down {
		button.is_down = is_down
		button.has_changed = true
	}
}

is_button_down :: proc(button: Button) -> b32 {
	return button.has_changed && button.is_down
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

update_audio_buffer :: proc(state: ^GameState, buffer: ^SoundBuffer, samples: i32){
    for i in 0..<samples{
        for c in 0..<buffer.channels{
            audio_buffer_index := i * buffer.channels + c
            buffer.data[audio_buffer_index] = u16(state.volume * math.sin(state.audio_t_sine))
        }
        state.audio_t_sine += 2.0 * math.PI * 1.0 / (f32(buffer.samples_per_second) / state.sine_wave)
	}
}

update :: proc(state: ^GameState, input: Input){
    // fmt.println("tick")

    if input.up.is_down{
    // if is_button_down(input.up){
        state.sine_wave += 100
        fmt.println("up")
    }

    // if is_button_down(input.down){
    if input.down.is_down{
        state.sine_wave -= 100
        fmt.println("down")
    }
}

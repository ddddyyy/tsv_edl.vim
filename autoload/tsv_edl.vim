function! tsv_edl#timecode_to_secs(timecode)
	let _tc = split(substitute(a:timecode, ',' , '.', 'g'), ":")
	let HH = str2nr(_tc[0])
	let MM = str2nr(_tc[1])
	let SS = str2float(_tc[2])
	return HH*3600.0+MM*60.0+SS
endfunction

function! tsv_edl#sec_to_timecode(sec)
	let HH = float2nr(a:sec/3600.0)
	let MM = float2nr((a:sec - HH*3600.0)/60.0)
	let SS = float2nr((a:sec - HH*3600.0 - MM*60.0))
	let MS = float2nr((a:sec - HH*3600.0 - MM*60.0 - SS)*1000.0)
	return printf("%02d:%02d:%02d.%03d", HH, MM, SS, MS)
endfunction


function! tsv_edl#infer_time_pos(line)
	"""""" infer current timecode
	let cursor_pos = getpos(".")[2] 
	let words_start_pos = matchstrpos(a:line, '|\t', 32, 1)[-1]  + 1.0
	let _p = (cursor_pos - words_start_pos) / (len(a:line) - words_start_pos)
	" FIXME wide chars
	let _p = _p > 0 ? _p : 0
	return _p
endfunction

function! tsv_edl#play_current_range(stop_at_end = v:true)
	let line=getline('.')
	if len(line) > 0
		let line_list = split(line, '\t')
		if line_list[0] == 'EDL' || line_list[0] == '---' || line_list[0] == 'xxx'
			let filename = trim(line_list[3],'|')
			let filename = trim(filename)
			let record_in = substitute(line_list[1], ',' , '.', 'g') 
			let record_out = substitute(line_list[2], ',' , '.', 'g') 
			"let command = 'ffplay -hide_banner -ss ' . record_in . ' ./*"' . filename . '"' . '*.!(tsv|srt|txt)'

			let cursor_pos_percentage = tsv_edl#infer_time_pos(line)

			"echo "[cursor_pos_percentage]: ".float2nr(cursor_pos_percentage*100)."%"
			let _rec_in_secs = tsv_edl#timecode_to_secs(record_in)
			let _rec_out_secs = tsv_edl#timecode_to_secs(record_out)
			let line_duration =  _rec_out_secs - _rec_in_secs
			let deduced_line_duration = line_duration * ( 1 - cursor_pos_percentage)
			"echo printf("[_rec_in_secs, _rec_out_secs, line_duration, deduced_line_duration]: %.3f, %.3f, %.3f, %.3f", _rec_in_secs, _rec_out_secs, line_duration, deduced_line_duration)
			let deduced_start_pos_secs = line_duration * cursor_pos_percentage + _rec_in_secs
			"echo "[deduced_start_pos_secs]: ". printf("%.3f", deduced_start_pos_secs)
			"
			let deduced_timecode = tsv_edl#sec_to_timecode(deduced_start_pos_secs)
			"echo "[deduced_timecode]: ". deduced_timecode

			"""""" command, go!
			"let command_play_from_start = 'ffplay -hide_banner -noborder -seek_interval 1 -ss ' . record_in . ' ./*"' . filename . '"' . '*.!(tsv|srt|txt)&'
			"let command_play_from_cursor = printf('ffplay -autoexit -hide_banner -noborder -seek_interval 1 -ss %s -t %.3f ./*"%s"*.!(tsv|srt|txt)', deduced_start_pos_secs, deduced_line_duration, filename)
			"let command_mpv_from_cursor = 'mpv --profile=low-latency --no-terminal --start='. deduced_timecode . ' --end='. record_out . ' ./*"' . filename . '"' . '*.!(tsv|srt|txt)'

			if a:stop_at_end == v:true
				let command_mpv_from_cursor = 'mpv --no-terminal --start='. deduced_timecode . ' --end='. record_out . ' "$(ls *"' . filename . '"* | ' . " sed '/srt$/d; /tsv$/d; /txt$/d;' | head -n1)\""
				" on the nested quote inside brackets
				" > Once one is inside $(...), quoting starts all over from scratch.
				" -- https://unix.stackexchange.com/questions/289574/nested-double-quotes-in-assignment-with-command-substitution
				"
				" --profile=low-latency 
				"echo '[Ctrl-C to stop.] '
				let prompt = "[mpv] " . filename . " " . deduced_timecode . " --> " . record_out
			else
				let command_mpv_from_cursor = 'mpv --no-terminal --start='. deduced_timecode . ' "$(ls *"' . filename . '"* | ' . " sed '/srt$/d; /tsv$/d; /txt$/d;' | head -n1)\""
				let prompt = "[mpv] " . filename . " " . deduced_timecode . " --> EOF"
			endif

			let command = command_mpv_from_cursor
			echo prompt
			call system(command)

			"silent execute "!".command
			redraw!
		endif
	endif
endfunction

function! tsv_edl#continous_play()
	call cursor(0,0) " current line, first column
	let next_line_number = search('^EDL', 'ncW')
	while next_line_number > 0
		call cursor(next_line_number, 0) " next line, first column
		redraw!
		call tsv_edl#play_current_range() 
		let next_line_number = search('^EDL', 'nW')
	endwhile
	" Reference {{{
	" https://stackoverflow.com/questions/22868834/how-can-i-execute-a-command-until-the-end-of-the-file-in-vim/22869952
	" You can write an explicit loop that stops when it reaches the last line:
	"     :while line('.') < line('$') | exe 'normal! 3Jj' | endwhile
	" Or you could just rely on the command sequence aborting when there are no more lines, and create a sufficiently long sequence:
	":    exe 'normal!' repeat('3Jj', 100)
	" }}}
endfunction

function! tsv_edl#break_line()
	let line=getline('.')
	if len(line) > 0
		let line_list = split(line, '\t')
		if line_list[0] == 'EDL' || line_list[0] == '---' || line_list[0] == 'xxx'
			let cursor_pos_percentage = tsv_edl#infer_time_pos(line)

			let _rec_in_secs = tsv_edl#timecode_to_secs(line_list[1])
			let _rec_out_secs = tsv_edl#timecode_to_secs(line_list[2])
			let line_duration =  _rec_out_secs - _rec_in_secs
			let deduced_start_pos_secs = line_duration * cursor_pos_percentage + _rec_in_secs
			"echo "[deduced_start_pos_secs]: ". printf("%.3f", deduced_start_pos_secs)
			let deduced_timecode = substitute(tsv_edl#sec_to_timecode(deduced_start_pos_secs), '\.', ',', 'g')
			"echo "[deduced_timecode]: ". deduced_timecode

			let words_start_pos = matchstrpos(line, '|\t', 32, 1)[-1] + 1
			"echo words_start_pos
			let break_pos = getpos(".")[2]

			let break_pos_relative  = break_pos - words_start_pos
			if break_pos_relative < 0
				echo "not a good break choice"
				return
			endif

			let _cur_words = line_list[4][:break_pos_relative-1]
			let _next_words = line_list[4][break_pos_relative:]

			let _cur_in = line_list[1]
			let _cur_out = line_list[2]

			let _cur_line = printf("%s\t%s\t%s\t%s\t%s",line_list[0], line_list[1], deduced_timecode, line_list[3], _cur_words)
			let _next_line = printf("%s\t%s\t%s\t%s\t%s",line_list[0], deduced_timecode, line_list[2], line_list[3], _next_words)

			call setline(".",_cur_line )
			call append(".", _next_line)
		endif
	endif
endfunction

function!  tsv_edl#join_with_next_line()
	let cur_line=getline('.')
	let next_line=getline(line('.')+1)
	let cur_line_end_col = col('$') "record the pos of EOL

	if len(cur_line) > 0 && len(next_line) > 0
		let cur_line_list = split(cur_line, '\t')
		let next_line_list = split(next_line, '\t')

		if (cur_line_list[0] == 'EDL' || cur_line_list[0] == '---' || cur_line_list[0] == 'xxx') 
					\ && (next_line_list[0] == 'EDL' || next_line_list[0] == '---' || next_line_list[0] == 'xxx')
			let tc1 = tsv_edl#timecode_to_secs(cur_line_list[2])
			let tc2 = tsv_edl#timecode_to_secs(next_line_list[1])

			if (tc2 < tc1)
				echohl WarningMsg
				echo "Refuse to join a gap with reversed time-space"
				echohl None
				return
			endif
			if (tc2 - tc1 > 10)
				echohl WarningMsg
				echo "Refuse to join a gap longer than 10 sec"
				echohl None
				return
			endif

			let a = cur_line_list[0]
			let b = cur_line_list[1]
			let c = next_line_list[2]
			if cur_line_list[3] !=# next_line_list[3]
				echohl WarningMsg
				echo "Cannot join different clips"
				echohl None
				return
			endif

			let d = cur_line_list[3]
			if (next_line_list[4] =~# "^[ SPACE ")
				let e = cur_line_list[4]
			else
				let e = cur_line_list[4] .' '. next_line_list[4]
			endif

			let new_line = printf("%s\t%s\t%s\t%s\t%s",a,b,c,d,e)
			call setline(".", new_line )
			call setline(line(".")+1, "")
			execute "normal! jddk"
			call cursor(0, cur_line_end_col) "place cursor right between the joined lines
			echo "Clips joined."
		endif
	endif
endfunction

"" see !shopt
""     extglob off

"======================
" IPC
"======================

let g:ipc_media_ready = v:false
let g:ipc_loaded_media_name = ""

function! tsv_edl#ipc_load_media()
	if g:ipc_media_ready
		call tsv_edl#ipc_quit()
		return
	endif

	if system("pgrep -f input-ipc-server=/tmp/mpvsocket")
		echon '[pgrep] existing mpvsocket found, reuse. '
		let result=system('echo { \"command\": [\"get_property\", \"filename\" ] } | socat - /tmp/mpvsocket 2>/dev/null | jq -r .data')
		"echo result
		let clipname = fnamemodify(result, ":r")
		"echo clipname
		let g:ipc_media_ready = v:true
		let g:ipc_loaded_media_name = clipname
	endif

	let line=getline('.')
	if len(line) == 0 | return | endif

	let line_list = split(line, '\t')
	if len(line_list) == 0 | return | endif
	if ! (line_list[0] == 'EDL' || line_list[0] == '---' || line_list[0] == 'xxx') | return | endif
	if line_list[1] !~# '\d\d:\d\d:\d\d,\d\d\d' | return | endif

	let filename = trim(trim(line_list[3],'|'))

	let start_tc = string(tsv_edl#timecode_to_secs( substitute(line_list[1], ',' , '.', 'g')))
	let command = 'mpv --no-terminal --input-ipc-server=/tmp/mpvsocket --no-focus-on-open --start=' . start_tc . ' --pause ' . '"$(ls *"' . filename . '"* | ' . " sed '/srt$/d; /tsv$/d; /txt$/d;' | head -n1)\"" . " &"
	echon command
	"echo "[mpv] load media: " . filename
	call system(command)
	if v:shell_error
		" FIXME doen't work for now
		echon '[mpv] could not load media. '
		let g:ipc_media_ready = v:false
		let g:ipc_loaded_media_name = ""
	else
		let g:ipc_media_ready = v:true
		let g:ipc_loaded_media_name = filename
		"sleep 500m
		"call tsv_edl#ipc_seek()
	endif
endfunction

function! tsv_edl#ipc_quit()
	"let command = 'echo { \"command\": [\"quit\"] } | socat - /tmp/mpvsocket > /dev/null &'
	let command = "pkill -f input-ipc-server=/tmp/mpvsocket"
	call system(command)
	let g:ipc_media_ready = v:false
	let g:ipc_loaded_media_name = ""
	echon "[mpv ipc] quit. "
endfunction

function! tsv_edl#ipc_seek()
	if ! g:ipc_media_ready
		echon "[mpv ipc] not loaded. press \\\\ to init or connect."
		return
	endif

	let line=getline('.')
	if len(line) == 0 | return | endif

	let line_list = split(line, '\t')
	if len(line_list) == 0 | return | endif
	if ! (line_list[0] == 'EDL' || line_list[0] == '---' || line_list[0] == 'xxx') | return | endif
	if line_list[1] !~# '\d\d:\d\d:\d\d,\d\d\d' | return | endif

	let filename = trim(trim(line_list[3],'|'))

	if filename !=# g:ipc_loaded_media_name
		echon "[mpv ipc] different clip, load new. "
		call tsv_edl#ipc_quit()
		call tsv_edl#ipc_load_media()
	endif

	let record_in = substitute(line_list[1], ',' , '.', 'g') 
	let record_out = substitute(line_list[2], ',' , '.', 'g') 

	let cursor_pos_percentage = tsv_edl#infer_time_pos(line)

	"echo "[cursor_pos_percentage]: ".float2nr(cursor_pos_percentage*100)."%"
	let _rec_in_secs = tsv_edl#timecode_to_secs(record_in)
	let _rec_out_secs = tsv_edl#timecode_to_secs(record_out)
	let line_duration =  _rec_out_secs - _rec_in_secs
	let deduced_line_duration = line_duration * ( 1 - cursor_pos_percentage)
	"echo printf("[_rec_in_secs, _rec_out_secs, line_duration, deduced_line_duration]: %.3f, %.3f, %.3f, %.3f", _rec_in_secs, _rec_out_secs, line_duration, deduced_line_duration)
	let deduced_start_pos_secs = line_duration * cursor_pos_percentage + _rec_in_secs
	"echo "[deduced_start_pos_secs]: ". printf("%.3f", deduced_start_pos_secs)
	"
	"let deduced_timecode = tsv_edl#sec_to_timecode(deduced_start_pos_secs)
	"echo "[deduced_timecode]: ". deduced_timecode

	"let command = 'mpvc -T '. string(deduced_start_pos_secs)  . ' &'
	let command = 'echo { \"command\": [\"set_property\", \"playback-time\", ' . string(deduced_start_pos_secs) . " ] } | socat - /tmp/mpvsocket > /dev/null &"
	" socat can be replaced by: nc -U -N $SOCKET
	let prompt = "[mpv ipc] seek to " . string(deduced_start_pos_secs) . "  "

	echon prompt
	call system(command)

	"silent execute "!".command
	redraw!
endfunction

function! tsv_edl#ipc_continous_play()
	call cursor(0,0) " current line, first column
	let next_line_number = search('^EDL', 'ncW')

	call system('echo { \"command\": [\"set_property\", \"pause\", false ] } | socat - /tmp/mpvsocket > /dev/null &')

	while next_line_number > 0
		call cursor(next_line_number, 0) " next line, first column
		redraw!

		let line=getline('.')
		if len(line) > 0
			let line_list = split(line, '\t')
			if line_list[0] == 'EDL' || line_list[0] == '---' || line_list[0] == 'xxx'
				let filename = trim(line_list[3],'|')
				let filename = trim(filename)
				let record_in = substitute(line_list[1], ',' , '.', 'g') 
				let record_out = substitute(line_list[2], ',' , '.', 'g') 

				let cursor_pos_percentage = tsv_edl#infer_time_pos(line)

				"echo "[cursor_pos_percentage]: ".float2nr(cursor_pos_percentage*100)."%"
				let _rec_in_secs = tsv_edl#timecode_to_secs(record_in)
				let _rec_out_secs = tsv_edl#timecode_to_secs(record_out)
				let line_duration =  _rec_out_secs - _rec_in_secs
				let deduced_line_duration = line_duration * ( 1 - cursor_pos_percentage)
				"echo printf("[_rec_in_secs, _rec_out_secs, line_duration, deduced_line_duration]: %.3f, %.3f, %.3f, %.3f", _rec_in_secs, _rec_out_secs, line_duration, deduced_line_duration)
				let deduced_start_pos_secs = line_duration * cursor_pos_percentage + _rec_in_secs
				"echo "[deduced_start_pos_secs]: ". printf("%.3f", deduced_start_pos_secs)
				"
				let deduced_timecode = tsv_edl#sec_to_timecode(deduced_start_pos_secs)
				"echo "[deduced_timecode]: ". deduced_timecode

				let command = 'echo { \"command\": [\"set_property\", \"playback-time\", ' . string(deduced_start_pos_secs) . " ] } | socat - /tmp/mpvsocket > /dev/null &"
				let prompt = "[mpv ipc] seek to " .  string(deduced_start_pos_secs)

				echo prompt
				call system(command)
				let sleeptime = float2nr(deduced_line_duration * 1000)
				exe 'sleep '. sleeptime . 'm'

				"silent execute "!".command
				redraw!
			endif
		endif

		let next_line_number = search('^EDL', 'nW')
	endwhile

	call system('echo { \"command\": [\"set_property\", \"pause\", true ] } | socat - /tmp/mpvsocket > /dev/null &')
endfunction

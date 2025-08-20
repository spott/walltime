# walltime.plugin.zsh
# Records wall time for the last N commands in the current interactive shell.
# Exports LAST_CMD_TIMES (text) and LAST_CMD_TIMES_JSON (JSON).
# Provides: cmdtime [N], cmdtime-clear, cmdtime-size N

# Only run in interactive shells.
[[ -o interactive ]] || return 0

emulate -L zsh
setopt typeset_silent
autoload -Uz add-zsh-hook 2>/dev/null || true
zmodload -F zsh/datetime b:strftime 2>/dev/null || true

typeset -gi WALLTIME_HIST_SIZE=${WALLTIME_HIST_SIZE:-20}

# State
typeset -ga _wall_hist_cmd=() _wall_hist_start=() _wall_hist_end=() _wall_hist_dur=() _wall_hist_status=()
typeset -gF _wall_cmd_start
typeset -g  _wall_cmd_text

# JSON escape for command text
_wall_json_escape() {
  emulate -L zsh
  local s="$1"
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  s=${s//$'\t'/\\t}
  print -r -- "$s"
}

# Export env vars snapshot
_wall_export_env() {
  emulate -L zsh
  local -a lines=()
  local json="["
  local i esc
  for (( i=1; i<=${#_wall_hist_cmd}; i++ )); do
    esc=$(_wall_json_escape "${_wall_hist_cmd[i]}")
    lines+=("${_wall_hist_dur[i]}|${_wall_hist_status[i]}|${_wall_hist_cmd[i]//$'\n'/\\n}")
    json+="{\"cmd\":\"$esc\",\"wall_s\":${_wall_hist_dur[i]},\"status\":${_wall_hist_status[i]},\"start\":${_wall_hist_start[i]},\"end\":${_wall_hist_end[i]}},"
  done
  json=${json%,}"]"
  typeset -gx LAST_CMD_TIMES="${(j:\n:)lines}"
  typeset -gx LAST_CMD_TIMES_JSON="$json"
}

# Hooks
_wall_preexec() { _wall_cmd_start=$EPOCHREALTIME; _wall_cmd_text="$1" }

_wall_precmd() {
  emulate -L zsh
  local status=$?
  if [[ -n ${_wall_cmd_text-} && -n ${_wall_cmd_start-} ]]; then
    local -F 6 end=$EPOCHREALTIME
    local -F 6 dur=$(( end - _wall_cmd_start ))
    _wall_hist_cmd+="${_wall_cmd_text}"
    _wall_hist_start+=$_wall_cmd_start
    _wall_hist_end+=$end
    _wall_hist_dur+=$dur
    _wall_hist_status+=$status
    while (( ${#_wall_hist_cmd} > WALLTIME_HIST_SIZE )); do
      shift _wall_hist_cmd _wall_hist_start _wall_hist_end _wall_hist_dur _wall_hist_status
    done
    _wall_export_env
    unset _wall_cmd_text _wall_cmd_start
  fi
}

# User-facing helpers
cmdtime() {
  emulate -L zsh
  local n=${1:-$WALLTIME_HIST_SIZE}
  local i start=$(( ${#_wall_hist_cmd} - n + 1 )); (( start < 1 )) && start=1
  for (( i=start; i<=${#_wall_hist_cmd}; i++ )); do
    printf '%8.3f s  [%3d]  %s\n' ${_wall_hist_dur[i]} ${_wall_hist_status[i]} "${_wall_hist_cmd[i]}"
  done
}

cmdtime-clear() {
  emulate -L zsh
  _wall_hist_cmd=() _wall_hist_start=() _wall_hist_end=() _wall_hist_dur=() _wall_hist_status=()
  typeset -gx LAST_CMD_TIMES=""
  typeset -gx LAST_CMD_TIMES_JSON="[]"
}

cmdtime-size() { emulate -L zsh; (( $# > 0 )) && typeset -gi WALLTIME_HIST_SIZE=$1 }

# Register hooks
add-zsh-hook preexec _wall_preexec
add-zsh-hook precmd  _wall_precmd

# Optional: managers may call this to unload
walltime#unload() {
  emulate -L zsh
  add-zsh-hook -d preexec _wall_preexec
  add-zsh-hook -d precmd  _wall_precmd
}

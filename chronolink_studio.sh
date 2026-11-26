#!/bin/bash
APP_NAME="CHRONOLINK STUDIO"
ENGINE_NAME="Powered by chronolink"
AUTHOR="INF_Specter"
VERSION="v1.1.1"
UPDATE_URL="https://githubusercontent.com"

CHRONO="adb shell /data/local/tmp/chronolink"
APP_DIR="$HOME/.chronolink_studio"
mkdir -p "$APP_DIR"
STATS="$APP_DIR/feedback_stats.log"; touch "$STATS"
CASE_DB="$APP_DIR/cases_10800.db"
STATE_FILE="$APP_DIR/timer.state"

BOLD="\033[1m"; DIM="\033[2m"; NC="\033[0m"
C_RED="\033[38;2;255;59;79m"; C_GREEN="\033[38;2;46;213;115m"; C_GOLD="\033[38;2;255;215;0m"
C_ICE="\033[38;2;130;230;255m"; C_WHITE="\033[38;2;245;246;250m"; C_CYAN="\033[38;2;0;210;255m"
C_PINK="\033[38;2;255;71;180m"; C_PURPLE="\033[38;2;165;94;234m"; C_GRAY="\033[38;2;140;150;165m"

THEME="XMAS"; LED_FRAME=0; DAILY_LIMIT_MINS=120; REMAINING_MINS="Not set"; MINS_SOURCE="PRESS [M]"
LAST_TICK_EPOCH=$(date +%s); LAST_TZ=""; BANNER=""
HISTORY_LOG=(); FAILED_LIST=()
TIMEZONE_PRESETS=("Europe/Athens" "America/New_York" "America/Denver" "America/Los_Angeles" "Pacific/Honolulu" "Etc/GMT+12" "Pacific/Auckland" "Asia/Dubai" "Africa/Nairobi" "America/Chicago" "Pacific/Marquesas")

play_intro_video() {
  tput civis; clear
  local cols=$(tput cols 2>/dev/null || echo 100); local rows=$(tput lines 2>/dev/null || echo 32)
  local vpad=$(( (rows - 14) / 2 )); [ "$vpad" -lt 1 ] && vpad=1
  local logo=(
    "  ██████╗██╗  ██╗██████╗  ██████╗ ███╗   ██╗ ██████╗ ██╗     ██╗███╗   ██╗██╗  ██╗"
    " ██╔════╝██║  ██║██╔══██╗██╔═══██╗████╗  ██║██╔═══██╗██║     ██║████╗  ██║██║ ██╔╝"
    " ██║     ███████║██████╔╝██║   ██║██╔██╗ ██║██║   ██║██║     ██║██╔██╗ ██║█████╔╝ "
    " ██║     ██╔══██║██╔══██╗██║   ██║██║╚██╗██║██║   ██║██║     ██║██║╚██╗██║██╔═██╗ "
    " ╚██████╗██║  ██║██║  ██║╚██████╔╝██║ ╚████║╚██████╔╝███████╗██║██║ ╚████║██║  ██╗"
    "  ╚═════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═══╝ ╚═════╝ ╚══════╝╚═╝╚═╝  ╚═══╝╚═╝  ╚═╝"
    "                         S   T   U   D   I   O     $VERSION                        "
  )
  local colors=("$C_RED" "$C_GOLD" "$C_GREEN" "$C_ICE" "$C_CYAN" "$C_PINK")
  for frame in 0 1 2 3 4 5; do
    tput cup $vpad 0; local col="${colors[$frame]}"
    for line in "${logo[@]}"; do
      local lpad=$(( (cols - ${#line}) / 2 )); [ "$lpad" -lt 0 ] && lpad=0
      printf "%*s${col}${BOLD}%s${NC}\n" "$lpad" "" "$line"
    done
    local sub="⚡ $ENGINE_NAME  •  Created by $AUTHOR ⚡"
    local spad=$(( (cols - ${#sub}) / 2 )); [ "$spad" -lt 0 ] && spad=0
    printf "\n%*s${C_WHITE}${BOLD}%s${NC}\n" "$spad" "" "$sub"
    local bar_len=$(( (frame + 1) * 8 ))
    local bar=$(printf "%0.s█" $(seq 1 $bar_len))
    local bpad=$(( (cols - 52) / 2 )); [ "$bpad" -lt 0 ] && bpad=0
    printf "\n%*s${C_GREEN}[%-48s]${NC}\n" "$bpad" "" "$bar"
    sleep 0.2
  done
  sleep 0.3; tput cnorm
}
save_timer_state() { echo "$(date +%s)|$REMAINING_MINS|$DAILY_LIMIT_MINS" > "$STATE_FILE"; }
auto_detect_mins() {
  if [ -s "$STATE_FILE" ]; then
    local ep=$(cut -d"|" -f1 "$STATE_FILE"); local rem=$(cut -d"|" -f2 "$STATE_FILE"); local lim=$(cut -d"|" -f3 "$STATE_FILE")
    [[ "$lim" =~ ^[0-9]+$ ]] && DAILY_LIMIT_MINS="$lim"
    if [[ "$rem" =~ ^[0-9]+$ ]] && [[ "$ep" =~ ^[0-9]+$ ]]; then
      local calc=$((rem - ( ($(date +%s) - ep) / 60 ) )); [ "$calc" -lt 0 ] && calc=0
      REMAINING_MINS="$calc"; MINS_SOURCE="AUTO-SAVED"; return
    fi
  fi
  REMAINING_MINS="Not set"; MINS_SOURCE="PRESS [M]"
}

is_failed() { for f in "${FAILED_LIST[@]}"; do [[ "$f" == "$1" ]] && return 0; done; return 1; }
next_preset_tz() {
  for tz in "${TIMEZONE_PRESETS[@]}"; do ! is_failed "$tz" && echo "$tz" && return; done
  FAILED_LIST=(); echo "${TIMEZONE_PRESETS[0]}"
}

get_suggestion() {
  SUGGEST_TZ=$(next_preset_tz)
  if [[ "$SUGGEST_TZ" == "Europe/Athens" ]]; then
    SUGGEST_REASON="Local Athens clock (00:00 EET reset)"
  else
    SUGGEST_REASON="Next preset ($(TZ="$SUGGEST_TZ" date "+%H:%M %Z"))"
  fi
}

apply_tz() { $CHRONO "$1"; LAST_TZ="$1"; HISTORY_LOG+=("$(date +%H:%M:%S) -> $1"); }
log_feedback() {
  local res="$1"; local target="${LAST_TZ:-$SUGGEST_TZ}"; local hr=$(date +%H)
  echo "$(date +%Y-%m-%d_%H:%M) | H=${hr} | M=${REMAINING_MINS} | TZ=${target} | ${res}" >> "$STATS"
  if [[ "$res" == "WORKED" ]]; then BANNER="${C_GREEN}${BOLD}[✓ LOGGED: $target WORKED at ${hr}:00]${NC}"
  else FAILED_LIST+=("$target"); get_suggestion; BANNER="${C_RED}${BOLD}[✗ LOGGED: $target -> Next: $SUGGEST_TZ]${NC}"; fi
}

led_string() {
  local f=$((LED_FRAME % 4))
  if [[ "$THEME" == "XMAS" ]]; then
    case $f in
      0) echo -e "${C_RED}◉${C_GRAY}━━${C_GREEN}◉${C_GRAY}━━${C_GOLD}✦${C_GRAY}━━${C_ICE}❄${C_GRAY}━━${C_RED}◉${C_GRAY}━━${C_GREEN}◉${C_GRAY}━━${C_GOLD}✦${C_GRAY}━━${C_ICE}❄${C_GRAY}━━${C_RED}◉${C_GRAY}━━${C_GREEN}◉${C_GRAY}━━${C_GOLD}✦${C_GRAY}━━${C_ICE}❄${C_GRAY}━━${C_RED}◉${C_GRAY}━━${C_GREEN}◉${C_GRAY}━━${C_GOLD}✦${C_GRAY}━━${C_ICE}❄${C_GRAY}━━${C_RED}◉${NC}" ;;
      1) echo -e "${C_ICE}❄${C_GRAY}━━${C_RED}◉${C_GRAY}━━${C_GREEN}◉${C_GRAY}━━${C_GOLD}✦${C_GRAY}━━${C_ICE}❄${C_GRAY}━━${C_RED}◉${C_GRAY}━━${C_GREEN}◉${C_GRAY}━━${C_GOLD}✦${C_GRAY}━━${C_ICE}❄${C_GRAY}━━${C_RED}◉${C_GRAY}━━${C_GREEN}◉${C_GRAY}━━${C_GOLD}✦${C_GRAY}━━${C_ICE}❄${C_GRAY}━━${C_RED}◉${C_GRAY}━━${C_GREEN}◉${C_GRAY}━━${C_GOLD}✦${C_GRAY}━━${C_ICE}❄${NC}" ;;
      2) echo -e "${C_GOLD}✦${C_GRAY}━━${C_ICE}❄${C_GRAY}━━${C_RED}◉${C_GRAY}━━${C_GREEN}◉${C_GRAY}━━${C_GOLD}✦${C_GRAY}━━${C_ICE}❄${C_GRAY}━━${C_RED}◉${C_GRAY}━━${C_GREEN}◉${C_GRAY}━━${C_GOLD}✦${C_GRAY}━━${C_ICE}❄${C_GRAY}━━${C_RED}◉${C_GRAY}━━${C_GREEN}◉${C_GRAY}━━${C_GOLD}✦${C_GRAY}━━${C_ICE}❄${C_GRAY}━━${C_RED}◉${C_GRAY}━━${C_GREEN}◉${C_GRAY}━━${C_GOLD}✦${NC}" ;;
      3) echo -e "${C_GREEN}◉${C_GRAY}━━${C_GOLD}✦${C_GRAY}━━${C_ICE}❄${C_GRAY}━━${C_RED}◉${C_GRAY}━━${C_GREEN}◉${C_GRAY}━━${C_GOLD}✦${C_GRAY}━━${C_ICE}❄${C_GRAY}━━${C_RED}◉${C_GRAY}━━${C_GREEN}◉${C_GRAY}━━${C_GOLD}✦${C_GRAY}━━${C_ICE}❄${C_GRAY}━━${C_RED}◉${C_GRAY}━━${C_GREEN}◉${C_GRAY}━━${C_GOLD}✦${C_GRAY}━━${C_ICE}❄${C_GRAY}━━${C_RED}◉${C_GRAY}━━${C_GREEN}◉${NC}" ;;
    esac
  else
    case $f in
      0) echo -e "${C_CYAN}◈${C_GRAY}══${C_PINK}◈${C_GRAY}══${C_PURPLE}◈${C_GRAY}══${C_GOLD}⚡${C_GRAY}══${C_CYAN}◈${C_GRAY}══${C_PINK}◈${C_GRAY}══${C_PURPLE}◈${C_GRAY}══${C_GOLD}⚡${C_GRAY}══${C_CYAN}◈${C_GRAY}══${C_PINK}◈${C_GRAY}══${C_PURPLE}◈${C_GRAY}══${C_GOLD}⚡${C_GRAY}══${C_CYAN}◈${C_GRAY}══${C_PINK}◈${C_GRAY}══${C_PURPLE}◈${C_GRAY}══${C_GOLD}⚡${C_GRAY}══${C_CYAN}◈${NC}" ;;
      1) echo -e "${C_GOLD}⚡${C_GRAY}══${C_CYAN}◈${C_GRAY}══${C_PINK}◈${C_GRAY}══${C_PURPLE}◈${C_GRAY}══${C_GOLD}⚡${C_GRAY}══${C_CYAN}◈${C_GRAY}══${C_PINK}◈${C_GRAY}══${C_PURPLE}◈${C_GRAY}══${C_GOLD}⚡${C_GRAY}══${C_CYAN}◈${C_GRAY}══${C_PINK}◈${C_GRAY}══${C_PURPLE}◈${C_GRAY}══${C_GOLD}⚡${C_GRAY}══${C_CYAN}◈${C_GRAY}══${C_PINK}◈${C_GRAY}══${C_PURPLE}◈${C_GRAY}══${C_GOLD}⚡${NC}" ;;
      2) echo -e "${C_PURPLE}◈${C_GRAY}══${C_GOLD}⚡${C_GRAY}══${C_CYAN}◈${C_GRAY}══${C_PINK}◈${C_GRAY}══${C_PURPLE}◈${C_GRAY}══${C_GOLD}⚡${C_GRAY}══${C_CYAN}◈${C_GRAY}══${C_PINK}◈${C_GRAY}══${C_PURPLE}◈${C_GRAY}══${C_GOLD}⚡${C_GRAY}══${C_CYAN}◈${C_GRAY}══${C_PINK}◈${C_GRAY}══${C_PURPLE}◈${C_GRAY}══${C_GOLD}⚡${C_GRAY}══${C_CYAN}◈${C_GRAY}══${C_PINK}◈${C_GRAY}══${C_PURPLE}◈${NC}" ;;
      3) echo -e "${C_PINK}◈${C_GRAY}══${C_PURPLE}◈${C_GRAY}══${C_GOLD}⚡${C_GRAY}══${C_CYAN}◈${C_GRAY}══${C_PINK}◈${C_GRAY}══${C_PURPLE}◈${C_GRAY}══${C_GOLD}⚡${C_GRAY}══${C_CYAN}◈${C_GRAY}══${C_PINK}◈${C_GRAY}══${C_PURPLE}◈${C_GRAY}══${C_GOLD}⚡${C_GRAY}══${C_CYAN}◈${C_GRAY}══${C_PINK}◈${C_GRAY}══${C_PURPLE}◈${C_GRAY}══${C_GOLD}⚡${C_GRAY}══${C_CYAN}◈${C_GRAY}══${C_PINK}◈${NC}" ;;
    esac
  fi
}

run_updater() {
  clear; tput cnorm
  echo -e "${C_CYAN}${BOLD}=== $APP_NAME SELF-UPDATER ($VERSION • by $AUTHOR) ===${NC}"
  echo -e "${DIM}Fetching latest version from GitHub (cache-busted)...${NC}\n"
  local tmp_file="/tmp/chronolink_studio_latest.sh"
  if curl -fsSL "${UPDATE_URL}?t=$(date +%s)" -o "$tmp_file" 2>/dev/null && grep -q "APP_NAME=" "$tmp_file"; then
    local remote_ver=$(grep -m1 '^VERSION=' "$tmp_file" | cut -d'"' -f2)
    echo -e "${C_GREEN}Latest version found: ${BOLD}${remote_ver:-Unknown}${NC} (Installed: $VERSION)"
    printf "${C_GOLD}Install update now and restart? [y/N]: ${NC}"; read up_ans
    if [[ "$up_ans" =~ ^[Yy]$ ]]; then
      cp "$tmp_file" "$0" && chmod +x "$0"
      [ -f "$HOME/tz_ultimate.sh" ] && cp "$tmp_file" "$HOME/tz_ultimate.sh" && chmod +x "$HOME/tz_ultimate.sh"
      echo -e "${C_GREEN}${BOLD}Updated to $remote_ver! Restarting...${NC}"; sleep 1
      exec "$0"
    fi
  else
    echo -e "${C_RED}Could not reach GitHub. Check your internet connection.${NC}"
  fi
  rm -f "$tmp_file"
  printf "\n${DIM}Press Enter to return...${NC}"; read
}
run_advisor() {
  clear; tput cnorm
  echo -e "${C_PINK}${BOLD}=== $APP_NAME AI ADVISOR [$VERSION • $ENGINE_NAME] ===${NC}"
  local last_pick=""
  while true; do
    printf "\n${C_CYAN}${BOLD}You > ${NC}"; read u
    [[ "$u" == "back" || "$u" == "exit" || "$u" == "q" ]] && break; [[ -z "$u" ]] && continue
    local m=$(echo "$u" | tr "[:upper:]" "[:lower:]"); local pick=""; local reply=""
    if [[ "$m" == "no" || "$m" == "next" || "$m" == *"another"* ]]; then
      [ -n "$last_pick" ] && FAILED_LIST+=("$last_pick"); get_suggestion; pick="$SUGGEST_TZ"
      reply="Next un-failed preset: $pick ($(TZ="$pick" date "+%H:%M %Z"))."
    elif [[ "$m" == *"reset"* || "$m" == *"athens"* ]]; then
      pick="Europe/Athens"; reply="Restoring Europe/Athens for 00:00 EET reset."
    else
      get_suggestion; pick="$SUGGEST_TZ"; reply="Phone: $(adb shell date 2>/dev/null || echo Unavailable). Preset: $pick ($SUGGEST_REASON)."
    fi
    last_pick="$pick"; echo -e "${C_PINK}${BOLD}AI  > ${NC}${C_WHITE}$reply${NC}"
    if [ -n "$pick" ]; then
      printf "${C_GOLD}Apply ($pick)? [y/n/Enter]: ${NC}"; read a
      [[ "$a" =~ ^[Yy]$ ]] && apply_tz "$pick"
      [[ "$a" =~ ^[Nn]$ ]] && FAILED_LIST+=("$pick")
    fi
  done
}

play_intro_video; auto_detect_mins; REDRAW_MENU=1
while true; do
  if [ "$REDRAW_MENU" -eq 1 ]; then
    REDRAW_MENU=0; get_suggestion
    rdev=$(adb devices | grep -w "device" | awk "{print \$1}"); [ -n "$rdev" ] && ds="${C_GREEN}${BOLD}● $rdev${NC}" || ds="${C_RED}${BOLD}● Disconnected${NC}"
    pdate=$(adb shell date 2>/dev/null); [ -z "$pdate" ] && pdate="${C_RED}Unavailable${NC}" || pdate="${C_WHITE}$pdate${NC}"
    w_cnt=$(grep -c "WORKED" "$STATS" 2>/dev/null); f_cnt=$(grep -c "FAILED" "$STATS" 2>/dev/null)
    COLS=$(tput cols 2>/dev/null || echo 100); ROWS=$(tput lines 2>/dev/null || echo 32)
    LPAD=$(( (COLS - 78) / 2 )); [ "$LPAD" -lt 0 ] && LPAD=0; VPAD=$(( (ROWS - 20) / 2 )); [ "$VPAD" -lt 1 ] && VPAD=1
    [[ "$THEME" == "XMAS" ]] && { BDR="$C_RED"; TITLE="🎄 $APP_NAME [$VERSION] • $ENGINE_NAME • by $AUTHOR 🎅"; } || { BDR="$C_CYAN"; TITLE="⚡ $APP_NAME [$VERSION] • $ENGINE_NAME • by $AUTHOR ⚡"; }
    clear; TOP_LED_ROW=$VPAD; tput cup $TOP_LED_ROW $((LPAD + 14)); led_string; R=$((TOP_LED_ROW + 1))
    tput cup $R $LPAD; echo -e "${BDR}${BOLD}╔════════════════════════════════════════════════════════════════════════════╗${NC}"
    tput cup $((R+1)) $LPAD; echo -e "${BDR}${BOLD}║${NC}  ${C_WHITE}${BOLD}${TITLE}${NC}"
    tput cup $((R+2)) $LPAD; echo -e "${BDR}${BOLD}╠════════════════════════════════════════════════════════════════════════════╣${NC}"
    tput cup $((R+3)) $LPAD; echo -e "${BDR}${BOLD}║${NC}  ${BOLD}Device:${NC} $ds  |  ${BOLD}Mins:${NC} ${C_GREEN}${REMAINING_MINS}${NC}  |  ${BOLD}Stats:${NC} ${C_GREEN}${w_cnt}W${NC}/${C_RED}${f_cnt}F${NC}  |  ${BOLD}Athens:${NC} $(date +%H:%M)"
    tput cup $((R+4)) $LPAD; echo -e "${BDR}${BOLD}║${NC}  ${BOLD}Phone :${NC} $pdate  ${BANNER}"
    tput cup $((R+5)) $LPAD; echo -e "${BDR}${BOLD}╠════════════════════════════════════════════════════════════════════════════╣${NC}"
    tput cup $((R+6)) $LPAD; echo -e "${BDR}${BOLD}║${NC}  ${C_GOLD}${BOLD}★ RECOMMENDED:${NC} ${C_GREEN}${BOLD}$SUGGEST_TZ${NC} ${DIM}($SUGGEST_REASON)${NC}"
    tput cup $((R+7)) $LPAD; echo -e "${BDR}${BOLD}╠════════════════════════════════════════════════════════════════════════════╣${NC}"
    tput cup $((R+8)) $LPAD; echo -e "${BDR}${BOLD}║${NC}   ${C_GOLD}${BOLD}[S]${NC} Apply Pick      ${C_GREEN}${BOLD}[Y]${NC} Log Worked (✓)  ${C_RED}${BOLD}[N]${NC} Next Pick (✗)   ${C_PINK}${BOLD}[A]${NC} AI Advisor"
    tput cup $((R+9)) $LPAD; echo -e "${BDR}${BOLD}║${NC}   ${C_PINK}${BOLD}[M]${NC} Set Mins/Limit  ${C_RED}${BOLD}[T]${NC} Reset Timer     ${C_CYAN}${BOLD}[W]${NC} World Clocks    ${C_CYAN}${BOLD}[D]${NC} Diagnostics"
    tput cup $((R+10)) $LPAD; echo -e "${BDR}${BOLD}║${NC}   ${C_ICE}${BOLD}[H]${NC} History Log     ${C_CYAN}${BOLD}[L]${NC} Stats Log       ${C_GREEN}${BOLD}[X]${NC} HD Theme        ${C_GOLD}${BOLD}[U]${NC} Self-Update"
    tput cup $((R+11)) $LPAD; echo -e "${BDR}${BOLD}╠════════════════════════════════════════════════════════════════════════════╣${NC}"
    tput cup $((R+12)) $LPAD; echo -e "${BDR}${BOLD}║${NC}   ${C_GREEN}${BOLD}[1]${NC} Athens (LOCAL)    ${C_ICE}${BOLD}[6]${NC} Honolulu (-12h)   ${C_ICE}${BOLD}[11]${NC} Auckland (+10h) ${C_ICE}${BOLD}[14]${NC} Dubai (+2h)"
    tput cup $((R+13)) $LPAD; echo -e "${BDR}${BOLD}║${NC}   ${C_ICE}${BOLD}[2]${NC} New York (-7h)    ${C_ICE}${BOLD}[7]${NC} Marquesas (-11.5) ${C_ICE}${BOLD}[12]${NC} Nairobi (+1h)   ${C_WHITE}${BOLD}[15]${NC} Full List"
    tput cup $((R+14)) $LPAD; echo -e "${BDR}${BOLD}║${NC}   ${C_ICE}${BOLD}[3]${NC} Chicago (-8h)     ${C_ICE}${BOLD}[8]${NC} Gambier (-11h)    ${C_ICE}${BOLD}[13]${NC} Cairo (+0h)     ${C_WHITE}${BOLD}[16]${NC} Search/TZ"
    tput cup $((R+15)) $LPAD; echo -e "${BDR}${BOLD}║${NC}   ${C_ICE}${BOLD}[4]${NC} Denver (-9h)      ${C_ICE}${BOLD}[9]${NC} Etc/GMT+12 (-14h) ${C_GREEN}${BOLD}[R]${NC} Safe Exit (Athens) ${C_RED}${BOLD}[0]${NC} Quit"
    tput cup $((R+16)) $LPAD; echo -e "${BDR}${BOLD}║${NC}   ${C_ICE}${BOLD}[5]${NC} LA (-10h)         ${C_ICE}${BOLD}[10]${NC} Etc/GMT-12 (+10h) ${C_CYAN}${BOLD}[F]${NC} Refresh         ${C_PINK}${BOLD}[I]${NC} Replay Intro"
    tput cup $((R+17)) $LPAD; echo -e "${BDR}${BOLD}╚══════════════════════════ Created by $AUTHOR ══════════════════════════╝${NC}"
    BOT_LED_ROW=$((R + 18)); PROMPT_ROW=$((R + 20))
  fi
  tput civis; tput cup $TOP_LED_ROW $((LPAD + 14)); led_string; tput cup $BOT_LED_ROW $((LPAD + 14)); led_string; tput cup $PROMPT_ROW $((LPAD + 22)); tput cnorm
  printf "${BOLD}Choice (HD LEDs live): ${NC}"
  if read -t 1 -n 1 c; then
    echo ""; REDRAW_MENU=1; APPLIED_NOW=0
    case "$c" in
      [Xx]) [[ "$THEME" == "XMAS" ]] && THEME="NEON" || THEME="XMAS" ;;
      [Ii]) play_intro_video ;; [Uu]) run_updater ;; [Ff]) continue ;;
      [Yy]) log_feedback "WORKED" ;; [Nn]) log_feedback "FAILED" ;; [Aa]) run_advisor ;;
      [Ss]) apply_tz "$SUGGEST_TZ"; APPLIED_NOW=1 ;;
      [Mm]) printf "Remaining mins: "; read im; [[ "$im" =~ ^[0-9]+$ ]] && REMAINING_MINS="$im" && save_timer_state ;;
      [Ww]) clear; for z in "Etc/GMT+12" "Pacific/Honolulu" "America/Los_Angeles" "America/Denver" "America/Chicago" "America/New_York" "Europe/Athens" "Africa/Nairobi" "Asia/Dubai" "Pacific/Auckland"; do printf "  %-22s -> %s\n" "$z" "$(TZ="$z" date "+%H:%M %Z")"; done; read ;;
      [Dd]) clear; echo "Engine: $ENGINE_NAME"; echo "ADB: $(adb devices | grep -w device)"; echo "TZ: $(adb shell getprop persist.sys.timezone)"; echo "Date: $(adb shell date)"; read ;;
      [Ll]) clear; cat "$STATS"; printf "\nPress Enter (or 'clear'): "; read cl; [[ "$cl" == "clear" ]] && > "$STATS" && FAILED_LIST=() ;;
      [Hh]) clear; printf "%s\n" "${HISTORY_LOG[@]:-None}"; read ;;
      [Tt]) printf "Mins until Athens reset: "; read tm; [[ "$tm" =~ ^[0-9]+$ ]] && sleep $((tm * 60)) && apply_tz "Europe/Athens" ;;
      1) printf "Second digit (0-6) or Enter for Athens: "; read -t 2 -n 1 c2; echo ""
         case "$c$c2" in 1) apply_tz "Europe/Athens"; APPLIED_NOW=1 ;; 10) apply_tz "Etc/GMT-12"; APPLIED_NOW=1 ;; 11) apply_tz "Pacific/Auckland"; APPLIED_NOW=1 ;; 12) apply_tz "Africa/Nairobi"; APPLIED_NOW=1 ;; 13) apply_tz "Africa/Cairo"; APPLIED_NOW=1 ;; 14) apply_tz "Asia/Dubai"; APPLIED_NOW=1 ;; 15) $CHRONO list | less ;; 16) printf "TZ or Keyword: "; read q; [[ "$q" == *"/"* ]] && { apply_tz "$q"; APPLIED_NOW=1; } || $CHRONO list | grep -i "$q" | less ;; esac ;;
      2) apply_tz "America/New_York"; APPLIED_NOW=1 ;; 3) apply_tz "America/Chicago"; APPLIED_NOW=1 ;;
      4) apply_tz "America/Denver"; APPLIED_NOW=1 ;; 5) apply_tz "America/Los_Angeles"; APPLIED_NOW=1 ;;
      6) apply_tz "Pacific/Honolulu"; APPLIED_NOW=1 ;; 7) apply_tz "Pacific/Marquesas"; APPLIED_NOW=1 ;;
      8) apply_tz "Pacific/Gambier"; APPLIED_NOW=1 ;; 9) apply_tz "Etc/GMT+12"; APPLIED_NOW=1 ;;
      [Rr]) apply_tz "Europe/Athens"; tput cnorm; exit 0 ;; 0) tput cnorm; exit 0 ;;
    esac
    if [ "$APPLIED_NOW" -eq 1 ]; then
      echo -e "\n${BOLD}Phone Now:${NC} ${C_GREEN}$(adb shell date 2>/dev/null)${NC}"
      printf "${C_GOLD}Did $LAST_TZ work? [y=Worked / n=Failed / Enter=Skip]: ${NC}"; read fb
      [[ "$fb" =~ ^[Yy]$ ]] && log_feedback "WORKED"; [[ "$fb" =~ ^[Nn]$ ]] && log_feedback "FAILED"
    fi
  else
    LED_FRAME=$((LED_FRAME + 1))
  fi
done

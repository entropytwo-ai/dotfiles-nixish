#!/usr/bin/env bash

# Colour helper (shadows `tput` for the calls below). Some consoles/SSH clients
# report TERM=vt102/vt220, whose terminfo has no colours, so real tput prints
# nothing - yet they render ANSI colours fine. Fall back to raw ANSI codes then,
# and downgrade 256-colour indexes on 8/16-colour terminals (TERM=linux turns
# `setaf 214` into a broken sequence). NO_COLOR or TERM=dumb disables colours.
_XT_NCOLORS=$(command tput colors 2>/dev/null) || _XT_NCOLORS=-1
[[ "$_XT_NCOLORS" =~ ^[0-9]+$ ]] || _XT_NCOLORS=-1
tput() {
  if [[ -n "${NO_COLOR:-}" || "${TERM:-dumb}" == dumb ]]; then return 0; fi
  case "$1" in
    setaf)
      local n=$2
      if (( n > 15 && _XT_NCOLORS < 256 )); then n=3; fi          # e.g. orange -> yellow
      if (( _XT_NCOLORS >= 8 )); then command tput setaf "$n" 2>/dev/null && return 0; fi
      if (( n < 8 )); then printf '\033[3%dm' "$n"
      elif (( n < 16 )); then printf '\033[9%dm' $((n - 8))
      else printf '\033[38;5;%dm' "$n"; fi ;;
    bold) printf '\033[1m' ;;
    sgr0) printf '\033[0m' ;;
    *)    command tput "$@" 2>/dev/null ;;
  esac
}

# Function to set color scheme
set_color_scheme() {
  local scheme=$1
  if [ "$scheme" == "alternative" ]; then
    COLOR_PERMISSIONS=$(tput setaf 4) # Blue
    COLOR_SIZE=$(tput setaf 2) # Green
    COLOR_DIRECTORY=$(tput setaf 1) # Red
    COLOR_BOLD_DIRECTORY=$(tput bold; tput setaf 1) # Bold Red
    COLOR_OWNER_GROUP=$(tput setaf 3) # Yellow
    COLOR_MODIFIED=$(tput setaf 6) # Cyan
    COLOR_FILE=$(tput setaf 5) # Magenta
    COLOR_BOLD_FILE=$(tput bold; tput setaf 5) # Bold Magenta
  elif [ "$scheme" == "christmas" ]; then
    COLOR_PERMISSIONS=$(tput setaf 2) # Green
    COLOR_SIZE=$(tput setaf 1) # Red
    COLOR_DIRECTORY=$(tput setaf 2) # Green
    COLOR_BOLD_DIRECTORY=$(tput bold; tput setaf 2) # Bold Green
    COLOR_OWNER_GROUP=$(tput setaf 1) # Red
    COLOR_MODIFIED=$(tput setaf 7) # White
    COLOR_FILE=$(tput setaf 1) # Red
    COLOR_BOLD_FILE=$(tput bold; tput setaf 1) # Bold Red
  elif [ "$scheme" == "halloween" ]; then
    COLOR_PERMISSIONS=$(tput setaf 3) # Yellow
    COLOR_SIZE=$(tput setaf 1) # Red
    COLOR_DIRECTORY=$(tput setaf 214) # Orange
    COLOR_BOLD_DIRECTORY=$(tput bold; tput setaf 214) # Bold Orange
    COLOR_OWNER_GROUP=$(tput setaf 1) # Red
    COLOR_MODIFIED=$(tput setaf 3) # Yellow
    COLOR_FILE=$(tput setaf 1) # Red
    COLOR_BOLD_FILE=$(tput bold; tput setaf 1) # Bold Red
    COLOR_WHITE=$(tput setaf 7) # White
  else
    COLOR_PERMISSIONS=$(tput setaf 5) # Default Purple
    COLOR_SIZE=$(tput setaf 3) # Default Yellow
    COLOR_DIRECTORY=$(tput setaf 6) # Default Teal
    COLOR_BOLD_DIRECTORY=$(tput bold; tput setaf 6) # Bold Teal
    COLOR_OWNER_GROUP=$(tput setaf 2) # Default Green
    COLOR_MODIFIED=$(tput setaf 5) # Default Purple
    COLOR_FILE=$(tput setaf 2) # Default Green
    COLOR_BOLD_FILE=$(tput bold; tput setaf 2) # Bold Green
  fi
  COLOR_RESET=$(tput sgr0)
}

# Function to print ASCII art based on the color scheme
print_ascii_art() {
  local scheme=$1
  if [ "$scheme" == "christmas" ]; then
    echo -e "${COLOR_BOLD_DIRECTORY}  *  ${COLOR_RESET}"
    echo -e "${COLOR_BOLD_DIRECTORY} *** ${COLOR_RESET}"
    echo -e "${COLOR_BOLD_DIRECTORY}*****${COLOR_RESET}"
    echo -e "${COLOR_BOLD_DIRECTORY}  |  ${COLOR_RESET}"
  elif [ "$scheme" == "halloween" ]; then
    echo -e "${COLOR_WHITE}  _____  ${COLOR_RESET}"
    echo -e "${COLOR_WHITE} /     \\ ${COLOR_RESET}"
    echo -e "${COLOR_WHITE}|(0) (0)|${COLOR_RESET}"
    echo -e "${COLOR_WHITE} \\  ^  / ${COLOR_RESET}"
    echo -e "${COLOR_WHITE}  |||||  ${COLOR_RESET}"
    echo -e "${COLOR_WHITE}  |||||  ${COLOR_RESET}"
  elif [ "$scheme" == "alternative" ]; then
    echo -e "${COLOR_BOLD_DIRECTORY}  /\\  ${COLOR_RESET}"
    echo -e "${COLOR_BOLD_DIRECTORY} /  \\ ${COLOR_RESET}"
    echo -e "${COLOR_BOLD_DIRECTORY}/____\\${COLOR_RESET}"
  else
    # Default scheme shows no ASCII art
    return
  fi
}

# Function to select a random theme
select_random_theme() {
  local themes=("default" "alternative" "christmas" "halloween")
  local random_index=$((RANDOM % ${#themes[@]}))
  echo "${themes[$random_index]}"
}

# Default color scheme
set_color_scheme "default"

# Configuration for column headers
HEADER_PERMISSIONS="Permissions"
HEADER_SIZE="Size"
HEADER_DIRECTORY="Name"
HEADER_OWNER_GROUP="Owner::Group"
HEADER_MODIFIED="Last Modified"
HEADER_ACL="ACL"

# Configuration for flag variables
FLAG_INCLUDE_FILES="f"
FLAG_MAX_DEPTH="L"
FLAG_SHOW_PERMISSIONS="p"
FLAG_SHOW_DATETIME="t"
FLAG_SHOW_USERGROUP="u"
FLAG_INCLUDE_HIDDEN="a"
FLAG_EXPORT_CSV="C"
FLAG_COLOR_SCHEME="s"
FLAG_RANDOM_THEME="r"
FLAG_SHOW_ACL="A"

# Function to escape special characters in a string
escape_special_chars() {
  local input="$1"
  echo "$input" | sed -e 's/\\/\\\\/g' -e 's/\"/\\"/g' -e 's/\t/\\t/g'
}

# Function to print ACL information
print_acl_info() {
  local path=$1
  local acl_output=$(getfacl -p "$path" 2>/dev/null | tail -n +2)
  echo -e "${COLOR_OWNER_GROUP}${acl_output}${COLOR_RESET}"
}

# Function to print directory entry information
print_entry_info() {
  local path=$1
  local show_permissions=$2
  local show_datetime=$3
  local show_usergroup=$4
  local show_acl=$5
  local export_csv=$6

  if [ ! -e "$path" ]; then
    echo "Error: $path does not exist"
    return
  fi

  local perms=""
  local size=""
  local owner=""
  local group=""
  local mod_date=""
  local acl=""

  if [ "$show_permissions" == true ]; then
    perms=$(ls -ld "$path" | awk '{print $1}') # captures permissions including ACL indication
  fi
  size=$(du -sh "$path" 2>/dev/null | cut -f1)
  if [ "$show_usergroup" == true ]; then
    owner=$(stat -c "%U" "$path" 2>/dev/null)
    group=$(stat -c "%G" "$path" 2>/dev/null)
  fi
  if [ "$show_datetime" == true ]; then
    mod_date=$(stat -c "%y" "$path" 2>/dev/null | cut -d'.' -f1)
  fi

  if [[ "$perms" == *"+" && "$show_acl" == true ]]; then
    acl=$(getfacl -p "$path" 2>/dev/null | tail -n +2 | tr '\n' ' ')
  fi

  owner=$(escape_special_chars "$owner")
  group=$(escape_special_chars "$group")

  if [ "$export_csv" == true ]; then
    local csv_output=""
    if [ "$show_permissions" == true ]; then
      csv_output+="$perms,"
    fi
    if [ "$show_usergroup" == true ]; then
      csv_output+="$owner::$group,"
    fi
    csv_output+="$size,"
    if [ "$show_datetime" == true ]; then
      csv_output+="$mod_date,"
    fi
    if [ "$show_acl" == true ]; then
      csv_output+="$acl,"
    fi
    csv_output+="\"$(basename "$path")\""
    echo "$csv_output" >> "$csv_file"
  else
    local output=""
    if [ "$show_permissions" == true ]; then
      output+="${COLOR_PERMISSIONS}${perms}${COLOR_RESET} "
    fi
    if [ "$show_usergroup" == true ]; then
      output+="${COLOR_OWNER_GROUP}${owner}::${group}${COLOR_RESET} "
    fi
    output+="${COLOR_SIZE}${size}${COLOR_RESET} "
    if [ "$show_datetime" == true ]; then
      output+="${COLOR_MODIFIED}${mod_date}${COLOR_RESET} "
    fi
    if [ -d "$path" ]; then
      output+="${COLOR_DIRECTORY}$(basename "$path")${COLOR_RESET}"
    else
      output+="${COLOR_FILE}$(basename "$path")${COLOR_RESET}"
    fi
    echo -e "$output"
    if [ "$show_acl" == true ] && [[ "$perms" == *"+" ]]; then
      print_acl_info "$path"
    fi
  fi
}

# Function to print tree structure with optional permissions, sizes, owner, group, and last modification date
print_tree() {
  local base_dir=$1
  local indent_level=$2
  local max_depth=$3
  local prefix=$4
  local include_files=$5
  local show_permissions=$6
  local show_datetime=$7
  local show_usergroup=$8
  local show_acl=$9
  local include_hidden=${10}
  local export_csv=${11}

  if [ $indent_level -gt $max_depth ]; then
    return
  fi

  local entries
  if [ "$include_hidden" == true ]; then
    entries=("$base_dir"/{,.[!.],..?}*)
  else
    entries=("$base_dir"/*)
  fi

  local total_entries=${#entries[@]}
  local index=0

  for entry in "${entries[@]}"; do
    if [ -d "$entry" ] || [ "$include_files" == true ]; then
      local connector="├──"
      if [ $((index + 1)) -eq $total_entries ]; then
        connector="└──"
      fi
      if [ "$export_csv" != true ]; then
        local output="${prefix}${connector} "
        echo -ne "$output"
      fi
      print_entry_info "$entry" $show_permissions $show_datetime $show_usergroup $show_acl $export_csv
      if [ -d "$entry" ]; then
        if [ $((index + 1)) -eq $total_entries ]; then
          print_tree "$entry" $((indent_level + 1)) $max_depth "${prefix}    " $include_files $show_permissions $show_datetime $show_usergroup $show_acl $include_hidden $export_csv
        else
          print_tree "$entry" $((indent_level + 1)) $max_depth "${prefix}│   " $include_files $show_permissions $show_datetime $show_usergroup $show_acl $include_hidden $export_csv
        fi
      fi
    fi
    ((index++))
  done
}

# Function to display usage
show_usage() {
  echo "Usage: $0 [options] /path/to/directory"
  printf "  -%s\t\t%s\n" "$FLAG_INCLUDE_FILES" "Include files"
  printf "  -%s max_depth\t%s\n" "$FLAG_MAX_DEPTH" "Set maximum depth for directory traversal"
  printf "  -%s\t\t%s\n" "$FLAG_SHOW_PERMISSIONS" "Show permissions"
  printf "  -%s\t\t%s\n" "$FLAG_SHOW_DATETIME" "Show modification date/time"
  printf "  -%s\t\t%s\n" "$FLAG_SHOW_USERGROUP" "Show owner and group"
  printf "  -%s\t\t%s\n" "$FLAG_INCLUDE_HIDDEN" "Include hidden files and directories"
  printf "  -%s csv_file\t%s\n" "$FLAG_EXPORT_CSV" "Export output to a CSV file"
  printf "  -%s scheme\t%s\n" "$FLAG_COLOR_SCHEME" "Select color scheme (default, alternative, christmas, halloween)"
  printf "  -%s\t\t%s\n" "$FLAG_RANDOM_THEME" "Randomly select a color scheme"
  printf "  -%s\t\t%s\n" "$FLAG_SHOW_ACL" "Show ACL information"
  exit 1
}

# Check if no arguments were provided
if [ $# -eq 0 ]; then
  show_usage
fi

# Initialize default values
include_files=false
max_depth=3
show_permissions=false
show_datetime=false
show_usergroup=false
include_hidden=false
show_acl=false
export_csv=false
csv_file=""
scheme="default"

# Parse the flags
while getopts "$FLAG_INCLUDE_FILES$FLAG_MAX_DEPTH:$FLAG_SHOW_PERMISSIONS$FLAG_SHOW_DATETIME$FLAG_SHOW_USERGROUP$FLAG_INCLUDE_HIDDEN$FLAG_EXPORT_CSV:$FLAG_COLOR_SCHEME:$FLAG_RANDOM_THEME$FLAG_SHOW_ACL" opt; do
  case $opt in
    $FLAG_INCLUDE_FILES)
      include_files=true
      ;;
    $FLAG_MAX_DEPTH)
      max_depth=$OPTARG
      ;;
    $FLAG_SHOW_PERMISSIONS)
      show_permissions=true
      ;;
    $FLAG_SHOW_DATETIME)
      show_datetime=true
      ;;
    $FLAG_SHOW_USERGROUP)
      show_usergroup=true
      ;;
    $FLAG_INCLUDE_HIDDEN)
      include_hidden=true
      ;;
    $FLAG_EXPORT_CSV)
      export_csv=true
      csv_file=$OPTARG
      ;;
    $FLAG_COLOR_SCHEME)
      scheme=$OPTARG
      set_color_scheme $scheme
      ;;
    $FLAG_RANDOM_THEME)
      scheme=$(select_random_theme)
      set_color_scheme $scheme
      ;;
    $FLAG_SHOW_ACL)
      show_acl=true
      ;;
    *)
      show_usage
      ;;
  esac
done
shift $((OPTIND - 1))

# Check if a directory was provided
if [ -z "$1" ]; then
  show_usage
fi

# Print ASCII art based on the selected color scheme
print_ascii_art $scheme

# Print the column headers
header=""
if [ "$show_permissions" == true ]; then
  header+="${COLOR_PERMISSIONS}${HEADER_PERMISSIONS}${COLOR_RESET} "
fi
if [ "$show_usergroup" == true ]; then
  header+="${COLOR_OWNER_GROUP}${HEADER_OWNER_GROUP}${COLOR_RESET} "
fi
header+="${COLOR_SIZE}${HEADER_SIZE}${COLOR_RESET} "
if [ "$show_datetime" == true ]; then
  header+="${COLOR_MODIFIED}${HEADER_MODIFIED}${COLOR_RESET} "
fi
header+="${BOLD}${COLOR_DIRECTORY}${HEADER_DIRECTORY}${COLOR_RESET}${NORMAL}"
if [ "$show_acl" == true ]; then
  header+=" ${COLOR_OWNER_GROUP}${HEADER_ACL}${COLOR_RESET}"
fi

if [ "$export_csv" == true ]; then
  csv_header=""
  if [ "$show_permissions" == true ]; then
    csv_header+="${HEADER_PERMISSIONS},"
  fi
  if [ "$show_usergroup" == true ]; then
    csv_header+="${HEADER_OWNER_GROUP},"
  fi
  csv_header+="${HEADER_SIZE},"
  if [ "$show_datetime" == true ]; then
    csv_header+="${HEADER_MODIFIED},"
  fi
  if [ "$show_acl" == true ]; then
    csv_header+="${HEADER_ACL},"
  fi
  csv_header+="${HEADER_DIRECTORY}"
  echo "$csv_header" > "$csv_file"
else
  echo -e "$header"
fi

# Start from the specified directory
start_dir=$1
print_entry_info "$start_dir" $show_permissions $show_datetime $show_usergroup $show_acl $export_csv

# Adjust the prefix for the first level to align with headers
print_tree "$start_dir" 1 $max_depth "" $include_files $show_permissions $show_datetime $show_usergroup $show_acl $include_hidden $export_csv

#!/bin/bash

# NAME: eyesome-src.sh
# PATH: /usr/local/bin
# DESC: Source (include) file for eyessome.sh, eyesome-sun.sh, eyesome-cfg.sh
# CALL: Include at program top with `. eyesome-src` or `source eyesome-src`.
# NOTE: You do not have to specify directory because $PATH is searched.
# DATE: Feb 17, 2017. Modified: Sep xx, 2018.


if [[ $(id -u) != 0 ]]; then # root powers needed to call this script
    echo >&2 $0 must be called with sudo powers
    exit 1
fi

# Must have the yad package.
command -v yad >/dev/null 2>&1 || { echo >&2 \
        "yad package required but it is not installed.  Aborting."; \
        exit 2; }

# $TERM variable may be missing when called via desktop shortcut
CurrentTERM=$(env | grep TERM)
if [[ $CurrentTERM == "" ]] ; then
    notify-send --urgency=critical \
    "$0 cannot be run from GUI without TERM environment variable."
    exit 1
fi

OLD_IFS=$IFS
IFS="|"

declare -a CfgArr

CFG_SUNCITY_NDX=0
CFG_SLEEP_NDX=1
CFG_AFTER_SUNRISE_NDX=2
CFG_BEFORE_SUNSET_NDX=3
CFG_TEST_SECONDS_NDX=4
# 6 spare fields
CFG_MON1_NDX=10
CFG_MON2_NDX=30
CFG_MON3_NDX=50
CFG_LAST_NDX=69
CFG_CURR_BRIGHTNESS_OFFSET=14
CFG_CURR_GAMMA_OFFSET=15

ConfigFilename=/usr/local/bin/.eyesome-cfg
SunsetFilename=/usr/local/bin/.eyesome-sunset
SunriseFilename=/usr/local/bin/.eyesome-sunrise
EyesomeDaemon=/usr/local/bin/eyesome.sh
CurrentBrightnessFilename=/tmp/display-current-brightness
CronStartEyesome=/etc/cron.d/start-eyesome
CronSunHours=/etc/cron.daily/daily-eyesome-sun
EyesomeSunProgram=/usr/local/bin/eyesome-sun.sh
WakeEyesome=/usr/local/bin/wake-eyesome.sh
SystemdWakeEyesome=/lib/systemd/system-sleep/systemd-wake-eyesome

# Monitor working storage
GetMonitorWorkSpace () {

    # Move configuration array monitor 1-3 to WorkSpace fields
    # $1 = CfgArr Starting Index Number
    
    i=$1
    MonNumber="${CfgArr[$((i++))]}"          # "1", "2" or "3"
    MonStatus="${CfgArr[$((i++))]}"          # "Enabled" / "Disabled"
    MonType="${CfgArr[$((i++))]}"            # "Hardware" / "Software"
    MonName="${CfgArr[$((i++))]}"            # "Laptop Display" / '50" Sony TV'
    MonHardwareName="${CfgArr[$((i++))]}"    # "intel_backlight" / "xrandr"
    MonXrandrName="${CfgArr[$((i++))]}"      # "eDP-1-1" (primary) / "HDMI-0", etc
    MonDayBrightness="${CfgArr[$((i++))]}"   # often half of real maximum brightness
    MonDayRed="${CfgArr[$((i++))]}"          # yad uses 6 decimal places. Gamma
    MonDayGreen="${CfgArr[$((i++))]}"        # broken down between Red:Green:Blue
    MonDayBlue="${CfgArr[$((i++))]}"         # built into single string
    MonNgtBrightness="${CfgArr[$((i++))]}"
    MonNgtRed="${CfgArr[$((i++))]}"
    MonNgtGreen="${CfgArr[$((i++))]}"
    MonNgtBlue="${CfgArr[$((i++))]}"
    MonCurrBrightness="${CfgArr[$((i++))]}"
    MonCurrGamma="${CfgArr[$((i++))]}"
    # 4 spare fields

} # GetMonitorWorkSpace


# Monitor working storage
SetMonitorWorkSpace () {

    # Move WorkSpace 1-3 into array for writing to disk
    # $1 = CfgArr Starting Index Number
    i=$1

    CfgArr[$((i++))]="$MonNumber"           # "1", "2" or "3"
    CfgArr[$((i++))]="$MonStatus"           # "Enabled" / "Disabled"
    CfgArr[$((i++))]="$MonType"             # "Hardware" / "Software"
    CfgArr[$((i++))]="$MonName"             # "Laptop Display" / '50" Sony TV'
    CfgArr[$((i++))]="$MonHardwareName"     # "intel_backlight" / "xrandr"
    CfgArr[$((i++))]="$MonXrandrName"       # "eDP-1-1" (primary) / "HDMI-0", etc
    CfgArr[$((i++))]="$MonDayBrightness"    # often half of real maximum brightness
    CfgArr[$((i++))]="$MonDayRed"           # yad uses 6 decimal places. Gamma
    CfgArr[$((i++))]="$MonDayGreen"         # broken down between Red:Green:Blue
    CfgArr[$((i++))]="$MonDayBlue"          # built into single string
    CfgArr[$((i++))]="$MonNgtBrightness"
    CfgArr[$((i++))]="$MonNgtRed"
    CfgArr[$((i++))]="$MonNgtGreen"
    CfgArr[$((i++))]="$MonNgtBlue"
    CfgArr[$((i++))]="$MonCurrBrightness"
    CfgArr[$((i++))]="$MonCurrGamma"
    # 4 spare fields

} # SetMonitorWorkSpace

declare aXrandr=()

InitXrandrArray () {

    # Array is used for each monitor and searched by name.
    # Save time to search on connected/disconnected, primary monitor,
    # brightness level, gamma level.

    #readarray aXrandr <<< $(xrandr --verbose --current)
    mapfile -t aXrandr < <(xrandr --verbose --current)
    
} # InitXrandrArray

SearchXrandrArray () {

    # Parms: $1 = xrandr monitor name to search for.
    fNameFnd=false
    fBrightnessFnd=false
    fGammaFnd=false
    fCrtcFnd=false
    XrandrConnection=disconnected
    XrandrPrimary=false
    XrandrGamma=""
    XrandrBrightness=""
    XrandrCRTC=""           # Laptop lid open value=0, lid closed=blank

    for (( i=0; i<"${#aXrandr[*]}"; i++ )) ; do

        line="${aXrandr[$i]}"
        
        # Have we looped to next monitor and not found search string?
        if [[ "$line" =~ " connected " ]] && [[ $fNameFnd == true ]] ; then
            break
        fi
        
        if [[ "$line" =~ ^"$MonXrandrName connected" ]]; then
            fNameFnd=true
            XrandrConnection=connected
            [[ "$line" =~ "primary" ]] && XrandrPrimary=true
        fi

        if [[ $fNameFnd == true ]] && [[ $fGammaFnd == false ]] ; then
            if [[ "$line" =~ "Gamma: " ]]; then
                fGammaFnd=true
                XrandrGamma="${line##* }"
                # TODO: Use `xgamma` for accuracy
            fi
        fi

        if [[ $fGammaFnd == true ]] && [[ $fBrightnessFnd == false ]] ; then
            if [[ "$line" =~ "Brightness: " ]]; then
                fBrightnessFnd=true
                XrandrBrightness="${line##* }"
            fi
        fi

        if [[ $fBrightnessFnd == true ]] && [[ $fCrtcFnd == false ]] ; then
            if [[ "$line" =~ "CRTC: " ]]; then
                fCrtcFnd=true
                XrandrCRTC="${line##* }"
                break
            fi
        fi
        
    done
    
} # SearchXrandrArray

CreateConfiguration () {

    # Initialize array to blanks because we have spare fields for future
    for ((i=0; i<=CFG_LAST_NDX; i++)); do
        CfgArr[$i]=" "
    done
    
    echo "Accessing internet for default country/city name"
    
    # When you type https://www.timeanddate.com/worldclock the second link
    # is your default country/city name. For `grep` parameter credits see:
    #    https://unix.stackexchange.com/questions/146749/grep-substring-between-quotes
    
    SunCity=$(wget -q -O- https://www.timeanddate.com/worldclock | grep -oP \
        '<div class=my-city__items><div class=my-city__item><a href="\K[^"]+' )

    # Change $SunCity from:  /worldclock/country/city
    #                   to:  https://www.timeanddate.com/sun/country/city
    
    SunCity="${SunCity/\/worldclock/https:\/\/www.timeanddate.com\/sun}"
    CfgArr[$CFG_SUN_NDX]="$SunCity"
    CfgArr[$CFG_SLEEP_NDX]=60
    CfgArr[$CFG_BEFORE_SUNSET_NDX]=90
    CfgArr[$CFG_AFTER_SUNRISE_NDX]=120
    CfgArr[$CFG_TEST_SECONDS_NDX]=5

    # Deafult maximum brightness (daytime settings)
    backlight=$(ls /sys/class/backlight)
    # If no hardware support use software, eg `xrandr`
    MonStatus="Enabled"                 # alternate = "Disabled"
    if [[ $backlight == "" ]]; then
        MonType="Software"
        MonName="xrandr controlled"
        backlight="xrandr"
        MonDayBrightness="1.000000"     # yad using 6 decimal places
    else
        MonType="Hardware"
        MonName="Laptop Display"
        # Current user set brightness level will be max brightness for us
        MonDayBrightness=$(cat "/sys/class/backlight/$backlight/brightness")
    fi

    MonHardwareName="$backlight"
    XrandrName=$(xrandr --current | grep primary)
    PrimaryMonitor=${XrandrName%% *}
    MonXrandrName="$PrimaryMonitor"     # "eDP-1-1" "LVDS1", etc.

    MonDayRed="1.000000"                # yad uses 6 decimal places. Gamma
    MonDayGreen="1.000000"              # broken down between Red:Green:Blue
    MonDayBlue="1.000000"               # built into single string
    MonDayGamma="$MonDayRed:$MonDayGreen:$MonDayBlue" # Not stored, just habit
    MinAfterSunrise="120"
    MinBeforeSunset="120"
    MonNgtBrightness="$MonDayBrightness"
    MonNgtRed="$MonDayRed"
    MonNgtGreen="$MonDayGreen"
    MonNgtBlue="$MonDayBlue"
    MonNgtGamma="$MonDayGamma"
    MinBeforeSunset="$MinAfterSunrise"
    MonCurrBrightness="$MonDayBrightness"
    MonCurrGamma="$MonDayGamma"
    
    MonNumber=1                         # others = "2" or "3"
    SetMonitorWorkSpace $CFG_MON1_NDX   # Set Monitor #1
    
    MonNumber=2
    MonType="Software"
    MonHardwareName="xrandr"
    MonName="xrandr controlled"
    MonDayBrightness="1.000000"
    MonNgtBrightness="$MonDayBrightness"
    MonCurrBrightness="$MonDayBrightness"
    
    XrandrName=$(xrandr --current | grep -v "$PrimaryMonitor" | grep -v dis | \
                grep connected )
    Monitor2=${XrandrName%% *}
    MonXrandrName="$Monitor2"
    
    # If Monitor2 blank no external TV / monitor attached
    if [[ "$Monitor2" == "" ]]; then MonStatus="Disabled"
                                else MonStatus="Enabled" ; fi

    SetMonitorWorkSpace $CFG_MON2_NDX   # Set Monitor #2
    
    MonNumber=3
    
    XrandrName=$(xrandr --current | grep -v "$PrimaryMonitor" | grep -v dis | \
                grep -v "$Monitor2" | grep connected )
    Monitor3=${XrandrName%% *}
    MonXrandrName="$Monitor3"
    
    # If Monitor2 blank no external TV / monitor attached
    if [[ "$Monitor3" == "" ]]; then MonStatus="Disabled"
                                else MonStatus="Enabled" ; fi

    SetMonitorWorkSpace $CFG_MON3_NDX   # Set Monitor #3

    # Do we want to write configuration file now or wait till user saves?
    # Test from command line & see | delimiter using: echo "${CfgArr[*]}"

} # CreateConfiguration

ReadConfiguration () {

    # Read hidden configuration file with entries separated by "|" into array
    if [[ -s "$ConfigFilename" ]] ; then
         IFS='|' read -ra CfgArr < "$ConfigFilename"
    else CreateConfiguration ; fi
    
    # If sunrise/set files missing, use default values
    if [[ -s "$SunriseFilename" ]]; then sunrise=$(cat "$SunriseFilename")
                                    else sunrise="6:32 am" ; fi
    
    if [[ -s "$SunsetFilename" ]];  then sunset=$(cat "$SunsetFilename")
                                    else sunset="8:37 pm" ; fi    

    SunHoursAddress="${CfgArr[CFG_SUNCITY_NDX]}"
    # cut yad's 6 decimal positions using "%.*"
    UpdateInterval="${CfgArr[CFG_SLEEP_NDX]%.*}"
    MinAfterSunrise="${CfgArr[CFG_AFTER_SUNRISE_NDX]%.*}"
    MinBeforeSunset="${CfgArr[CFG_BEFORE_SUNSET_NDX]%.*}"
    TestSeconds="${CfgArr[CFG_TEST_SECONDS_NDX]%.*}"

    # Internal array of Xrandr all setings for faster searches
    aXrandr=( $(xrandr --verbose --current) )

} # ReadConfiguration

WriteConfiguration () {

    # write hidden configuration file using array
    echo "${CfgArr[*]}" > "$ConfigFilename"

} # WriteConfiguration

CalcNew () {

    # Sets NewReturn to new value
    # Parm: 1= Source Value (9999.999999)
    #       2= Target Value (9999.999999)
    #       3= Progress .999999 in six decimals

    st=$(echo "$1 < $2" | bc)

    if [[ $st -eq 1 ]] ; then
        # Target >= Source
        Diff=$( bc <<< "scale=6; $2 - $1" )
        Diff=$( bc <<< "scale=6; $Diff * $3" )
        NewReturn=$( bc <<< "scale=6; $2 - $Diff" )
    else
        # Target < Source
        Diff=$( bc <<< "scale=6; $1 - $2" )
        Diff=$( bc <<< "scale=6; $Diff * $3" )
        NewReturn=$( bc <<< "scale=6; $2 + $Diff" )
    fi

} # CalcNew

CalcBrightness () {

    NewGamma=""
    NewBrightness=""
    
    # Parms $1=Day / Night
    #       $2=Adjust factor (percentage in .999999)
    #       If $2 not passed then return Day or Night value without adjustment

    # Values may be going up or going down. Calc difference based on %

    if [[ $1 == Day ]]; then
        # Transitioning to Daytime
        if [[ -z "$2" ]]; then
            # Parameter 2 is empty (no adjustment percentage)
            NewGamma="$MonDayRed:$MonDayGreen:$MonDayBlue"
            NewBright="$MonDayBrightness"
        else
            CalcNew $MonNgtRed $MonDayRed $2
            NewRed=$NewReturn
            CalcNew $MonNgtGreen $MonDayGreen $2
            NewGreen=$NewReturn
            CalcNew $MonNgtBlue $MonDayBlue $2
            NewBlue=$NewReturn
            NewGamma="$NewRed:$NewGreen:$NewBlue"

            CalcNew $MonNgtBrightness $MonDayBrightness $2
            NewBright=$NewReturn
        fi
    else
        # Transitioning to Nighttime
        if [[ -z "$2" ]]; then
            NewGamma="$MonNgtRed:$MonNgtGreen:$MonNgtBlue"
            NewBright="$MonNgtBrightness"
        else
            # Parameter 2 passed. Use it as adjustment factor.
            CalcNew $MonDayRed $MonNgtRed $2
            NewRed=$NewReturn
            CalcNew $MonDayGreen $MonNgtGreen $2
            NewGreen=$NewReturn
            CalcNew $MonDayBlue $MonNgtBlue $2
            NewBlue=$NewReturn
            NewGamma="$NewRed:$NewGreen:$NewBlue"

            CalcNew $MonDayBrightness $MonNgtBrightness $2
            NewBright=$NewReturn
        fi
    fi

} # CalcBrightness

SetBrightness () {

    # Called from: - eyesome.sh for long day/night sleep no $2
    #              - eyesome.sh for short transition period with $2
    #              - eyesome-cfg.sh for short day/night test no $2

    # Parm: $1 = Day (can include increasing after sunrise)
    #            Ngt (can include decreasing before sunset)
    #       $2 = % fractional adjustment (6 decimals)
    #       If $2 not passed then use full day or full night values
 
    # Note: Day can be less than night. ie Red Gamma @ Day = 1.0, Ngt = 1.2   

    aMonNdx=( $CFG_MON1_NDX $CFG_MON2_NDX $CFG_MON3_NDX )
    InitXrandrArray
    aAllMon=()      # Must be visible to eyesome-cfg.sh
    
    for MonNdx in ${aMonNdx[@]}; do
    
        GetMonitorWorkSpace $MonNdx

        aAllMon+=("# ")
        aAllMon+=("# Monitor Number: $MonNumber")
        aAllMon+=("# Name: $MonName")
        aAllMon+=("# Status: $MonStatus")
        SearchXrandrArray $MonXrandrName
        aAllMon+=("# Connection: $XrandrConnection")
        aAllMon+=("# Xrandr CRTC: $XrandrCRTC")
       
        [[ $XrandrConnection == disconnected ]] && continue
        [[ $XrandrCRTC == "" ]] && continue
        [[ $MonStatus == Disabled ]] && continue

        CalcBrightness $1 $2
        Gamma=$NewGamma

        if [[ $MonType == "Hardware" ]]; then
            backlight="/sys/class/backlight/$MonHardwareName/brightness"
            Brightness=1.00    # Fake for xrandr below
            
            IntBrightness=${NewBright%.*}
            bash -c "echo $IntBrightness | sudo tee $backlight" > /dev/null

            [[ $MonNumber == "1" ]] && echo "$IntBrightness" > \
                                            "$CurrentBrightnessFilename"
            MonCurrBrightness="$IntBrightness"
        else
            # Software brightness control
            Brightness=$(printf %.2f $NewBright)
            [[ $MonNumber == "1" ]] && echo "$Brightness" > \
                                            "$CurrentBrightnessFilename"
            MonCurrBrightness="$Brightness"
        fi
        
        xRetn=$(xrandr --output $MonXrandrName --gamma $Gamma \
                --brightness $Brightness)

        MonCurrGamma="$Gamma"
        SetMonitorWorkSpace "$MonNdx"

    done
    
    WriteConfiguration

} # SetBrightness



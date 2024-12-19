#!/bin/bash

# ============= Configuration =============
API_BASE="https://api-pub.bitfinex.com/v2"
TICKER_BTC_USD="tBTCUSD"
TICKER_BTC_EUR="tBTCEUR"
CANDLE_BTC_DAILY="candles/trade:1D:tBTCUSD/last"
CANDLE_BTC_MONTHLY="candles/trade:1M:tBTCUSD/last"
UPDATE_INTERVAL=2

# Colors
COLOR_RESET="\033[0m"
COLOR_GREEN="\033[1;32m"
COLOR_BLUE="\033[34m"
COLOR_YELLOW="\033[33m"

# Chart commands
CHART_COMMANDS=(
    "bitcoin-chart-cli --hours 24 -h 11 -w 70"
    "bitcoin-chart-cli --days 30 -h 11 -w 70"
    "bitcoin-chart-cli --toplist 10 -w 70"
)

# Global variables
LAST_PRICE_USD=""
ITERATION_COUNT=0
CHART_FILE="/tmp/bitcoin_chart_output.txt"

# ============= Functions =============

fetch_ticker() {
    local symbol="$1"
    curl -s "$API_BASE/ticker/$symbol"
}

fetch_daily_candle() {
    curl -s "$API_BASE/$CANDLE_BTC_DAILY"
}

fetch_monthly_candle() {
    curl -s "$API_BASE/$CANDLE_BTC_MONTHLY"
}

get_last_price_from_ticker() {
    local ticker_json="$1"
    if [ -n "$ticker_json" ] && [[ "$ticker_json" != *"error"* ]]; then
        echo "$ticker_json" | jq -r '.[6]'
    else
        echo ""
    fi
}

get_daily_high_low() {
    local ticker_json="$1"
    if [ -n "$ticker_json" ] && [[ "$ticker_json" != *"error"* ]]; then
        local high=$(echo "$ticker_json" | jq -r '.[8]')
        local low=$(echo "$ticker_json" | jq -r '.[9]')
        echo "$high $low"
    else
        echo ""
    fi
}

get_monthly_high_low() {
    local candle_json="$1"
    if [ -n "$candle_json" ] && [[ "$candle_json" != *"error"* ]]; then
        local mh=$(echo "$candle_json" | jq -r '.[3]')
        local ml=$(echo "$candle_json" | jq -r '.[4]')
        echo "$mh $ml"
    else
        echo ""
    fi
}

format_number() {
    local num="$1"
    local integer_part="${num%.*}"
    local decimal_part="${num#*.}"

    if [ "$integer_part" = "$num" ]; then
        # No decimals
        formatted=$(echo "$integer_part" | sed ':a;s/\([0-9]\)\([0-9]\{3\}\)\b/\1.\2/;ta')
    else
        # Has decimals
        formatted_int=$(echo "$integer_part" | sed ':a;s/\([0-9]\)\([0-9]\{3\}\)\b/\1.\2/;ta')
        formatted="${formatted_int},${decimal_part}"
    fi
    echo "$formatted"
}

format_diff() {
    # Takes a numerical difference and formats with a sign and a dollar
    local diff="$1"
    if (( $(echo "$diff >= 0" | bc -l) )); then
        # positive or zero
        echo "+$(format_number "$diff")\$"
    else
        # negative
        # remove the minus sign for formatting
        local positive_part=$(echo "$diff" | sed 's/-//')
        echo "-$(format_number "$positive_part")\$"
    fi
}

print_title() {
    echo -e "${COLOR_BLUE}$(echo "BitcoinPrice" | figlet -f small)${COLOR_RESET}"
}

print_main_price() {
    local price_usd="$1"
    echo -e "${COLOR_YELLOW}$(echo "$price_usd" | figlet -d figlet_fonts -f Roman)${COLOR_RESET}"
}

print_eur_and_diffs() {
    local eur="$1"
    local daily_diff="$2"
    local monthly_diff="$3"
    echo -e "${COLOR_GREEN}Price in EUR:${COLOR_RESET} $eur ${COLOR_GREEN}|| Daily Diff:${COLOR_RESET} $daily_diff ${COLOR_GREEN}| Monthly Diff:${COLOR_RESET} $monthly_diff"
}

print_stats() {
    local dh="$1" dl="$2" mh="$3" ml="$4"
    echo -e "${COLOR_GREEN}Daily High/Low:${COLOR_RESET} ↑$dh ↓$dl ${COLOR_GREEN}| Monthly High/Low:${COLOR_RESET} ↑$mh ↓$ml"
}

fetch_chart_output() {
    local chart_index=$(( (ITERATION_COUNT / 2) % 3 ))
    ${CHART_COMMANDS[$chart_index]} > "$CHART_FILE" 2>/dev/null
}

print_chart() {
    cat "$CHART_FILE"
}

fetch_all_data() {
    BTC_USD_JSON=$(fetch_ticker "$TICKER_BTC_USD")
    BTC_EUR_JSON=$(fetch_ticker "$TICKER_BTC_EUR")
    BTC_MONTHLY_JSON=$(fetch_monthly_candle)
    BTC_DAILY_JSON=$(fetch_daily_candle)
}

prepare_data() {
    # Current USD price
    local usd_price=$(get_last_price_from_ticker "$BTC_USD_JSON")
    if [ -z "$usd_price" ]; then
        usd_price="$LAST_PRICE_USD"
    else
        LAST_PRICE_USD="$usd_price"
    fi

    # EUR price
    local eur_price=$(get_last_price_from_ticker "$BTC_EUR_JSON")

    # Daily stats
    read daily_high daily_low <<< "$(get_daily_high_low "$BTC_USD_JSON")"

    # Monthly stats
    read monthly_high monthly_low <<< "$(get_monthly_high_low "$BTC_MONTHLY_JSON")"

    # Daily and monthly candle data to get open prices
    local daily_open=$(echo "$BTC_DAILY_JSON" | jq -r '.[1]' 2>/dev/null)
    local monthly_open=$(echo "$BTC_MONTHLY_JSON" | jq -r '.[1]' 2>/dev/null)

    # Calculate differences (make sure data is not empty)
    # If daily_open or monthly_open fail, default to 0 to avoid errors
    if [ -z "$daily_open" ] || [ "$daily_open" = "null" ]; then
        daily_open="$usd_price"
    fi
    if [ -z "$monthly_open" ] || [ "$monthly_open" = "null" ]; then
        monthly_open="$usd_price"
    fi

    local daily_diff=$(echo "$usd_price - $daily_open" | bc -l)
    local monthly_diff=$(echo "$usd_price - $monthly_open" | bc -l)

    # Format all prices
    FORMATTED_USD="$(format_number "$usd_price")\$"
    FORMATTED_EUR="$(format_number "$eur_price")€"
    FORMATTED_DAILY_HIGH="$(format_number "$daily_high")\$"
    FORMATTED_DAILY_LOW="$(format_number "$daily_low")\$"
    FORMATTED_MONTHLY_HIGH="$(format_number "$monthly_high")\$"
    FORMATTED_MONTHLY_LOW="$(format_number "$monthly_low")\$"

    FORMATTED_DAILY_DIFF="$(format_diff "$daily_diff")"
    FORMATTED_MONTHLY_DIFF="$(format_diff "$monthly_diff")"
}

print_dashboard() {
    clear
    print_title
    print_main_price "$FORMATTED_USD"
    # Previously this line showed ETH/LTC and EUR. Now we show EUR and daily/monthly diff
    print_eur_and_diffs "$FORMATTED_EUR" "$FORMATTED_DAILY_DIFF" "$FORMATTED_MONTHLY_DIFF"
    print_stats "$FORMATTED_DAILY_HIGH" "$FORMATTED_DAILY_LOW" "$FORMATTED_MONTHLY_HIGH" "$FORMATTED_MONTHLY_LOW"
    print_chart
}

# ============= Main Loop =============
while true; do
    fetch_all_data
    prepare_data
    fetch_chart_output
    print_dashboard
    ((ITERATION_COUNT++))
    sleep $UPDATE_INTERVAL
done

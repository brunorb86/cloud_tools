#!/opt/homebrew/bin/bash

# Throttling Monitor v0.1
# Scans pods that start with "dev-" and compares throttling
# values over a 10-minute interval.

# -----------------------------------------------------
#  AKS CPU Throttling Monitor v0.5
#  - Environment selection menu
#  - Pod filtering by environment prefix
#  - 100% macOS Bash 3.2 compatible (no arrays)
# -----------------------------------------------------

# -----------------------------------------------------
#  AKS CPU Throttling Monitor v0.6
#  - Environment selection menu
#  - Option to scan ALL pods or only selected services
#  - POSIX compatible
# -----------------------------------------------------

# -----------------------------------------------------
# AKS CPU Throttling Monitor v0.7
# - Environment selection
# - All services or custom service list
# - Custom interval (minutes)
# - POSIX / macOS Bash 3.2 compatible
# -----------------------------------------------------

# ----------------------------
# Helper functions
# ----------------------------
get_throttling() {
    ns="$1"
    pod="$2"

    stats=$(kubectl -n "$ns" exec "$pod" -- cat /sys/fs/cgroup/cpu.stat 2>/dev/null)

    nr_periods=$(echo "$stats" | grep nr_periods | awk '{print $2}')
    nr_throttled=$(echo "$stats" | grep nr_throttled | awk '{print $2}')

    echo "$nr_periods,$nr_throttled"
}

classify() {
    delta="$1"
    if [ "$delta" -le 0 ]; then
        echo "No throttling"
    elif [ "$delta" -lt 100 ]; then
        echo "Low throttling"
    elif [ "$delta" -lt 1000 ]; then
        echo "Medium throttling"
    elif [ "$delta" -lt 5000 ]; then
        echo "High throttling"
    else
        echo "Severe throttling"
    fi
}

# ----------------------------
# Header
# ----------------------------
echo "------------------------------------------"
echo " AKS CPU Throttling Monitor"
echo "------------------------------------------"
echo ""

# ----------------------------
# Environment Selection
# ----------------------------
echo "Select environment:"
echo "1) Dev"
echo "2) UAT"
echo "3) Prod"
echo ""

read -p "Enter choice (1-3): " choice

case "$choice" in
    1)
        ENV="dev"
        FILTER_PREFIX="dev-"
        ;;
    2)
        ENV="uat"
        FILTER_PREFIX="uat-"
        ;;
    3)
        ENV="prod"
        FILTER_PREFIX="prod-"
        ;;
    *)
        echo "Invalid environment selection."
        exit 1
        ;;
esac

echo ""
echo "Environment selected: $ENV"
echo ""

# ----------------------------
# Service selection
# ----------------------------
echo "Do you want to:"
echo "1) Check ALL services in this environment"
echo "2) Provide a service list"
echo ""

read -p "Enter choice (1-2): " svc_choice

if [ "$svc_choice" = "2" ]; then
    echo ""
    echo "Enter a comma-separated list of service names."
    echo "Example: pdfstatements,alerts,dequeue"
    read -p "Services: " svc_list

    svc_regex=$(echo "$svc_list" | sed 's/,/|/g')
    FILTER="($FILTER_PREFIX)($svc_regex)"

    echo ""
    echo "Filtering services with regex:"
    echo "$FILTER"
else
    FILTER="$FILTER_PREFIX"
    echo ""
    echo "Scanning ALL services with prefix:"
    echo "$FILTER"
fi

echo ""

# ----------------------------
# Interval selection
# ----------------------------
echo "How many minutes do you want to wait between measurements?"
echo "Examples: 5, 10, 30, 60"
echo ""

read -p "Interval (minutes): " INTERVAL_MIN

# Basic validation (numeric + >0)
case "$INTERVAL_MIN" in
    ''|*[!0-9]*)
        echo "Invalid interval. Please enter a number."
        exit 1
        ;;
    0)
        echo "Interval must be greater than 0."
        exit 1
        ;;
esac

INTERVAL=$(( INTERVAL_MIN * 60 ))

echo ""
echo "Interval set to $INTERVAL_MIN minute(s) ($INTERVAL seconds)"
echo ""

# ----------------------------
# Discover pods
# ----------------------------
pods=$(kubectl get pods -A --no-headers | grep -E "$FILTER" | awk '{print $1":"$2}')

if [ -z "$pods" ]; then
    echo "No pods found for filter: $FILTER"
    exit 0
fi

mkdir -p /tmp/throttle_start
mkdir -p /tmp/throttle_end

# ----------------------------
# First snapshot
# ----------------------------
echo "Collecting initial throttling snapshot..."
for entry in $pods; do
    ns=$(echo "$entry" | cut -d: -f1)
    pod=$(echo "$entry" | cut -d: -f2)
    filename="${ns}_${pod}"

    vals=$(get_throttling "$ns" "$pod")
    echo "$vals" > "/tmp/throttle_start/${filename}"

    echo "[$ns/$pod] start: $vals"
done

echo ""
echo "Sleeping for $INTERVAL seconds..."
sleep "$INTERVAL"

# ----------------------------
# Second snapshot
# ----------------------------
echo ""
echo "Collecting second throttling snapshot..."
for entry in $pods; do
    ns=$(echo "$entry" | cut -d: -f1)
    pod=$(echo "$entry" | cut -d: -f2)
    filename="${ns}_${pod}"

    vals=$(get_throttling "$ns" "$pod")
    echo "$vals" > "/tmp/throttle_end/${filename}"

    echo "[$ns/$pod] end: $vals"
done

# ----------------------------
# Delta Analysis
# ----------------------------
echo ""
echo "------------------------------------------"
echo " Throttling Delta Analysis"
echo "------------------------------------------"

no_thr=""
low_thr=""
medium_thr=""
high_thr=""
severe_thr=""

for entry in $pods; do
    ns=$(echo "$entry" | cut -d: -f1)
    pod=$(echo "$entry" | cut -d: -f2)
    filename="${ns}_${pod}"

    start_vals=$(cat "/tmp/throttle_start/${filename}")
    end_vals=$(cat "/tmp/throttle_end/${filename}")

    start_th=$(echo "$start_vals" | cut -d, -f2)
    end_th=$(echo "$end_vals" | cut -d, -f2)

    delta=$(( end_th - start_th ))
    severity=$(classify "$delta")

    line="[$ns/$pod] Δ=$delta (${start_th}→${end_th})"

    case "$severity" in
        "No throttling") no_thr="${no_thr}\n$line" ;;
        "Low throttling") low_thr="${low_thr}\n$line" ;;
        "Medium throttling") medium_thr="${medium_thr}\n$line" ;;
        "High throttling") high_thr="${high_thr}\n$line" ;;
        "Severe throttling") severe_thr="${severe_thr}\n$line" ;;
    esac
done

# ----------------------------
# Output
# ----------------------------
echo ""
echo "=== NO THROTTLING ==="
[ -z "$no_thr" ] && echo "None" || echo -e "$no_thr"

echo ""
echo "=== LOW THROTTLING ==="
[ -z "$low_thr" ] && echo "None" || echo -e "$low_thr"

echo ""
echo "=== MEDIUM THROTTLING ==="
[ -z "$medium_thr" ] && echo "None" || echo -e "$medium_thr"

echo ""
echo "=== HIGH THROTTLING ==="
[ -z "$high_thr" ] && echo "None" || echo -e "$high_thr"

echo ""
echo "=== SEVERE THROTTLING ==="
[ -z "$severe_thr" ] && echo "None" || echo -e "$severe_thr"

echo ""
echo "Done."

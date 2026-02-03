# AKS CPU Throttling Monitor

A bash script for monitoring CPU throttling in Azure Kubernetes Service (AKS) pods across different environments.

## What is CPU Throttling?

CPU throttling occurs when a container reaches its CPU limit defined in Kubernetes resource constraints. When this happens, the Linux kernel's CFS (Completely Fair Scheduler) throttles the container's CPU usage by pausing its execution for brief periods.

### The Silent Performance Killer

CPU throttling is particularly insidious because it causes **silent performance degradation** that can be difficult to diagnose:

- **Increased Latency**: Requests take longer to process without obvious errors
- **Intermittent Slowdowns**: Performance degrades unpredictably under load
- **Hidden Resource Starvation**: Applications appear healthy but respond slowly
- **Cascading Failures**: Downstream services experience timeouts due to upstream throttling
- **Metrics Confusion**: CPU utilization may look "normal" while throttling is severe

Traditional monitoring often misses throttling because:
- CPU usage percentages don't show throttling events
- No errors are logged
- Application metrics show increased latency but don't indicate the root cause
- The container continues running, just slower

This script helps you identify throttling issues **before they impact users** by measuring the actual throttling counters exposed by the Linux cgroup system.

## Features

- **Environment Selection**: Choose between Dev, UAT, or Prod environments
- **Flexible Service Filtering**: Monitor all services or specify a custom list
- **Customizable Intervals**: Set your preferred measurement interval in minutes
- **Severity Classification**: Automatically categorizes throttling levels:
  - No throttling (0 events)
  - Low throttling (1-99 events)
  - Medium throttling (100-999 events)
  - High throttling (1,000-4,999 events)
  - Severe throttling (5,000+ events)
- **Delta Analysis**: Compares throttling values over time to show actual impact

## Prerequisites

- `kubectl` installed and configured
- Access to your AKS cluster(s)
- Bash shell (compatible with macOS Bash 3.2 and POSIX shells)
- Permissions to exec into pods in target namespaces

## How It Works

1. **Discovery**: Scans all pods matching your environment prefix (e.g., `dev-`, `uat-`, `prod-`)
2. **First Snapshot**: Reads `/sys/fs/cgroup/cpu.stat` from each pod to capture initial throttling counters
3. **Wait Period**: Sleeps for your specified interval (e.g., 10 minutes)
4. **Second Snapshot**: Reads the same counters again
5. **Delta Analysis**: Calculates the difference in throttling events and categorizes severity

The script specifically monitors two key metrics from the cgroup CPU controller:
- `nr_periods`: Number of enforcement periods
- `nr_throttled`: Number of times the cgroup was throttled

## Usage

### Basic Usage

```bash
chmod +x throttle_monitor.sh
./throttle_monitor.sh
```

### Interactive Prompts

**1. Select Environment:**
```
Select environment:
1) Dev
2) UAT
3) Prod

Enter choice (1-3): 1
```

**2. Choose Service Scope:**
```
Do you want to:
1) Check ALL services in this environment
2) Provide a service list

Enter choice (1-2): 2
```

**3. Specify Services (if option 2 selected):**
```
Enter a comma-separated list of service names.
Example: pdfstatements,alerts,dequeue
Services: api,worker,scheduler
```

**4. Set Interval:**
```
How many minutes do you want to wait between measurements?
Examples: 5, 10, 30, 60

Interval (minutes): 10
```

### Example Output

```
=== NO THROTTLING ===
[prod/prod-api-7d8f9b5c4-xk2m1] Δ=0 (1234→1234)

=== LOW THROTTLING ===
[prod/prod-worker-6c9d8a7b5-pq3n2] Δ=45 (5678→5723)

=== MEDIUM THROTTLING ===
[prod/prod-scheduler-5b8c7d6a4-mn4k3] Δ=567 (9012→9579)

=== HIGH THROTTLING ===
[prod/prod-processor-4a7b6c5d3-lm5j4] Δ=2341 (12345→14686)

=== SEVERE THROTTLING ===
[prod/prod-queue-3d6c5b4a2-kl6h5] Δ=8923 (23456→32379)
```

## Customization

### Changing Environment Prefixes

If your cluster uses different naming conventions, modify the environment selection section:

```bash
case "$choice" in
    1)
        ENV="dev"
        FILTER_PREFIX="dev-"        # Change this to your prefix
        ;;
    2)
        ENV="staging"               # Change environment name
        FILTER_PREFIX="stg-"        # Change this to your prefix
        ;;
    3)
        ENV="production"            # Change environment name
        FILTER_PREFIX="prd-"        # Change this to your prefix
        ;;
```

### Adjusting Severity Thresholds

Modify the `classify()` function to match your performance requirements:

```bash
classify() {
    delta="$1"
    if [ "$delta" -le 0 ]; then
        echo "No throttling"
    elif [ "$delta" -lt 100 ]; then      # Adjust these thresholds
        echo "Low throttling"
    elif [ "$delta" -lt 1000 ]; then     # based on your tolerance
        echo "Medium throttling"
    elif [ "$delta" -lt 5000 ]; then     # for throttling events
        echo "High throttling"
    else
        echo "Severe throttling"
    fi
}
```

## Interpreting Results

### Throttling Delta (Δ)

The delta represents the **number of throttling events** that occurred during your monitoring interval:

- **Δ = 0**: No throttling occurred - your CPU limits are adequate
- **Δ = 1-99**: Minimal throttling - generally acceptable for most workloads
- **Δ = 100-999**: Moderate throttling - may cause noticeable latency spikes
- **Δ = 1,000-4,999**: Significant throttling - definitely impacting performance
- **Δ = 5,000+**: Severe throttling - critical performance degradation

### Recommended Actions

- **Low Throttling**: Monitor but no immediate action needed
- **Medium Throttling**: Review CPU requests/limits, consider increasing limits
- **High Throttling**: Increase CPU limits or optimize application performance
- **Severe Throttling**: Urgent action required - increase limits and investigate code efficiency

## Troubleshooting

### "No pods found for filter"

- Verify your kubectl context is correct: `kubectl config current-context`
- Check that pods exist with your prefix: `kubectl get pods -A | grep <prefix>`
- Ensure the filter regex matches your pod naming convention

### Permission Denied Errors

- Verify you have exec permissions: `kubectl auth can-i create pods/exec -n <namespace>`
- Check your RBAC configuration

### "cat: can't open '/sys/fs/cgroup/cpu.stat'"

- Your pods might use cgroup v2. Try `/sys/fs/cgroup/cpu/cpu.stat` instead
- Some minimal base images might not expose cgroup stats

## Contributing

Feel free to submit issues or pull requests to improve this tool.

## License

This script is provided as-is for monitoring AKS workloads.

## Version History

- **v0.7**: Added customizable interval selection
- **v0.6**: Added service filtering options
- **v0.5**: Environment selection menu
- **v0.1**: Initial release with basic throttling detection

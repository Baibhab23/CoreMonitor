function updateDashboard() {
    fetch('monitor_data.json')
        .then(response => response.json())
        .then(data => {
            document.getElementById('cpu').innerHTML = `CPU: ${data.cpu}%`;
            document.getElementById('memory').innerHTML = `Memory: ${data.memory.percent}% (Used: ${data.memory.used}MB, Total: ${data.memory.total}MB)`;
            document.getElementById('disk').innerHTML = `Disk Usage: ${data.disk}%`;
            document.getElementById('network').innerHTML = `Network: ${JSON.stringify(data.network)}`;
            document.getElementById('battery').innerHTML = `Battery: ${data.battery}`;
            document.getElementById('uptime').innerHTML = `Uptime: ${data.uptime}`;

            data.cpu > 80
                ? document.getElementById('cpu').classList.add('warning')
                : document.getElementById('cpu').classList.remove('warning');

            data.memory.percent > 80
                ? document.getElementById('memory').classList.add('warning')
                : document.getElementById('memory').classList.remove('warning');

            data.disk > 85
                ? document.getElementById('disk').classList.add('warning')
                : document.getElementById('disk').classList.remove('warning');
        })
        .catch(error => console.error('Error fetching monitor_data.json:', error));
}

async function loadCSVCharts() {
    const response = await fetch('usage_history.csv');
    const csv = await response.text();
    const lines = csv.trim().split('\n');
    const data = lines.slice(1).map(line => {
        const [timestamp, cpu, memory, rx, tx] = line.split(',');
        return {
            timestamp,
            cpu: parseFloat(cpu),
            memory: parseFloat(memory),
            rx: parseFloat(rx),
            tx: parseFloat(tx)
        };
    });

    // Select every 10th record
    const interval = 10;
    const filteredData = data.filter((_, index) => index % interval === 0);

    const labels = filteredData.map(d => d.timestamp);
    const cpuData = filteredData.map(d => d.cpu);
    const memData = filteredData.map(d => d.memory);
    const rxData = filteredData.map(d => d.rx);
    const txData = filteredData.map(d => d.tx);

    new Chart(document.getElementById('cpuChart'), {
        type: 'line',
        data: {
            labels,
            datasets: [{
                label: 'CPU (%)',
                data: cpuData,
                borderColor: 'red',
                tension: 0.3
            }]
        }
    });

    new Chart(document.getElementById('memChart'), {
        type: 'line',
        data: {
            labels,
            datasets: [{
                label: 'Memory (%)',
                data: memData,
                borderColor: 'blue',
                tension: 0.3
            }]
        }
    });

    new Chart(document.getElementById('netChart'), {
        type: 'line',
        data: {
            labels,
            datasets: [
                {
                    label: 'RX (bytes)',
                    data: rxData,
                    borderColor: 'green',
                    tension: 0.3
                },
                {
                    label: 'TX (bytes)',
                    data: txData,
                    borderColor: 'orange',
                    tension: 0.3
                }
            ]
        }
    });
}


// Initial load
updateDashboard();
loadCSVCharts();
setInterval(updateDashboard, 5000);

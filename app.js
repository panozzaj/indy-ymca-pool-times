// Indy YMCA Pool Times - Static Site JS

let scheduleData = null;
let branchData = null;
let selectedBranches = new Set();
let map = null;
let markers = {};

async function init() {
  try {
    const [scheduleRes, branchRes] = await Promise.all([
      fetch('data/schedule.json'),
      fetch('data/branches.json')
    ]);

    if (!scheduleRes.ok) throw new Error('Failed to load schedule data');
    if (!branchRes.ok) throw new Error('Failed to load branch data');

    scheduleData = await scheduleRes.json();
    branchData = await branchRes.json();

    initMap();
    renderSchedule();
    updateLastUpdated();
  } catch (error) {
    document.getElementById('schedule-container').innerHTML =
      `<p class="error">Error loading schedule: ${error.message}</p>`;
  }
}

// Check if a branch has any sessions across all days
function branchHasSessions(branchKey) {
  const branch = scheduleData.branches.find(b => b.key === branchKey);
  if (!branch) return false;
  return Object.values(branch.schedule).some(sessions => sessions.length > 0);
}

// Get branches from URL query params
function getBranchesFromUrl() {
  const params = new URLSearchParams(window.location.search);
  const branchesParam = params.get('branches');
  if (branchesParam) {
    return branchesParam.split(',').map(b => b.trim().toLowerCase());
  }
  return null;
}

// Update URL with current selection
function updateUrl() {
  const params = new URLSearchParams(window.location.search);
  if (selectedBranches.size > 0) {
    params.set('branches', Array.from(selectedBranches).join(','));
  } else {
    params.delete('branches');
  }
  const newUrl = params.toString()
    ? `${window.location.pathname}?${params.toString()}`
    : window.location.pathname;
  window.history.replaceState({}, '', newUrl);
}

function initMap() {
  // Center on Indianapolis
  map = L.map('map').setView([39.82, -86.22], 9);

  L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
    attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
  }).addTo(map);

  // Determine which branches are active (have sessions)
  const activeBranchKeys = branchData
    .filter(b => branchHasSessions(b.key))
    .map(b => b.key);

  const inactiveBranchKeys = branchData
    .filter(b => !branchHasSessions(b.key))
    .map(b => b.key);

  // Get initial selection from URL or default to all active
  const urlBranches = getBranchesFromUrl();
  let initialSelection;

  if (urlBranches) {
    initialSelection = urlBranches.filter(key => activeBranchKeys.includes(key));
  } else {
    initialSelection = activeBranchKeys;
  }

  initialSelection.forEach(key => selectedBranches.add(key));

  // Add markers for each branch
  branchData.forEach(branch => {
    const isActive = activeBranchKeys.includes(branch.key);
    const isSelected = selectedBranches.has(branch.key);

    const marker = L.circleMarker([branch.lat, branch.lng], {
      radius: 12,
      fillColor: getMarkerColor(isActive, isSelected),
      color: '#fff',
      weight: 2,
      opacity: 1,
      fillOpacity: isActive ? 0.9 : 0.4
    }).addTo(map);

    // Tooltip with branch name and area
    const tooltipText = branch.area ? `${branch.name} (${branch.area})` : branch.name;
    marker.bindTooltip(tooltipText, {
      permanent: false,
      direction: 'top',
      offset: [0, -10]
    });

    // Click to toggle selection (only for active branches)
    if (isActive) {
      marker.on('click', () => toggleBranch(branch.key));
      marker.getElement()?.classList.add('clickable');
    }

    markers[branch.key] = marker;
  });

  // Show inactive branches info
  if (inactiveBranchKeys.length > 0) {
    const names = inactiveBranchKeys.map(key => {
      const b = branchData.find(br => br.key === key);
      if (!b) return key;
      return b.area ? `${b.name} (${b.area})` : b.name;
    });
    document.getElementById('disabled-branches-info').textContent =
      `No lap swim times: ${names.join(', ')}`;
  }

  updateUrl();
}

function getMarkerColor(isActive, isSelected) {
  if (!isActive) return '#999';  // Gray for inactive
  return isSelected ? '#2563eb' : '#ddd';  // Blue for selected, light for unselected
}

function toggleBranch(key) {
  if (selectedBranches.has(key)) {
    selectedBranches.delete(key);
  } else {
    selectedBranches.add(key);
  }

  // Update marker style
  const marker = markers[key];
  if (marker) {
    marker.setStyle({
      fillColor: getMarkerColor(true, selectedBranches.has(key))
    });
  }

  updateUrl();
  renderSchedule();
}

// Build URL to original YMCA schedule page
function buildSourceUrl(branchId, dayStr) {
  // dayStr is like "Mon 12/01" - need to convert to YYYY-MM-DD
  const match = dayStr.match(/(\d+)\/(\d+)/);
  if (!match) return null;

  const month = parseInt(match[1]);
  const day = parseInt(match[2]);

  // Use generated_at to determine year (handle year rollover)
  const generatedDate = new Date(scheduleData.generated_at);
  let year = generatedDate.getFullYear();
  // If month is less than generated month - 6, assume next year
  if (month < generatedDate.getMonth() + 1 - 6) {
    year++;
  }

  const date = `${year}-${month.toString().padStart(2, '0')}-${day.toString().padStart(2, '0')}`;
  const params = new URLSearchParams({
    BranchID: branchId,
    search: 'pool time',
    date: date
  });
  return `https://indy.recliquecore.com/classes/printer_friendly/?${params}`;
}

// Parse time string to minutes since midnight for comparison
function timeToMinutes(timeStr) {
  const match = timeStr.match(/(\d+):(\d+)\s*(AM|PM)/i);
  if (!match) return 0;
  let hours = parseInt(match[1]);
  const minutes = parseInt(match[2]);
  const period = match[3].toUpperCase();
  if (period === 'PM' && hours !== 12) hours += 12;
  if (period === 'AM' && hours === 12) hours = 0;
  return hours * 60 + minutes;
}

// Format minutes since midnight to time string
function minutesToTime(mins) {
  let hours = Math.floor(mins / 60);
  const minutes = mins % 60;
  const period = hours >= 12 ? 'PM' : 'AM';
  if (hours > 12) hours -= 12;
  if (hours === 0) hours = 12;
  return `${hours}:${minutes.toString().padStart(2, '0')} ${period}`;
}

// Get sessions with gaps (closed times) inserted
function getSessionsWithGaps(sessions) {
  if (!sessions || sessions.length === 0) return [];

  const result = [];
  for (let i = 0; i < sessions.length; i++) {
    const session = sessions[i];

    // Check for gap before this session (except for first session)
    if (i > 0) {
      const prevEnd = timeToMinutes(sessions[i - 1].end_time);
      const currStart = timeToMinutes(session.start_time);
      if (currStart > prevEnd) {
        result.push({
          start_time: minutesToTime(prevEnd),
          end_time: minutesToTime(currStart),
          lanes: null,
          isClosed: true
        });
      }
    }

    result.push({ ...session, isClosed: false });
  }
  return result;
}

function renderSchedule() {
  const container = document.getElementById('schedule-container');

  if (selectedBranches.size === 0) {
    container.innerHTML = '<p class="no-selection">Click branches on the map to view schedules</p>';
    return;
  }

  const branches = scheduleData.branches.filter(b => selectedBranches.has(b.key));
  const days = scheduleData.days;

  if (days.length === 0) {
    container.innerHTML = '<p class="no-selection">No schedule data available</p>';
    return;
  }

  let html = '';

  days.forEach(day => {
    html += `<div class="day-section">`;
    html += `<h2 class="day-header">${day}</h2>`;
    html += `<div class="branches-grid" style="--branch-count: ${branches.length}">`;

    branches.forEach(branch => {
      const rawSessions = branch.schedule[day] || [];
      const sessions = getSessionsWithGaps(rawSessions);
      const branchInfo = branchData.find(b => b.key === branch.key);
      const areaText = branchInfo?.area ? ` (${branchInfo.area})` : '';
      const sourceUrl = buildSourceUrl(branch.id, day);

      html += `<div class="branch-column">`;
      if (sourceUrl) {
        html += `<h3 class="branch-name"><a href="${sourceUrl}" target="_blank" rel="noopener">${branch.name}${areaText}</a></h3>`;
      } else {
        html += `<h3 class="branch-name">${branch.name}${areaText}</h3>`;
      }

      if (rawSessions.length === 0) {
        html += `<p class="no-sessions">No lap swim</p>`;
      } else {
        html += `<ul class="session-list">`;
        sessions.forEach(session => {
          if (session.isClosed) {
            // Gap between sessions - pool may be used for classes, not necessarily closed
            html += `<li class="session closed">
              <span class="time">${session.start_time} - ${session.end_time}</span>
              <span class="lanes">No lap swim</span>
            </li>`;
          } else {
            html += `<li class="session">
              <span class="time">${session.start_time} - ${session.end_time}</span>
              <span class="lanes">${session.lanes}</span>
            </li>`;
          }
        });
        html += `</ul>`;
      }

      html += `</div>`;
    });

    html += `</div></div>`;
  });

  container.innerHTML = html;
}

function updateLastUpdated() {
  const date = new Date(scheduleData.generated_at);
  const formatted = date.toLocaleString('en-US', {
    weekday: 'long',
    year: 'numeric',
    month: 'long',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
    timeZoneName: 'short'
  });
  document.getElementById('last-updated').textContent = `Schedule last updated: ${formatted}`;
}

// Start the app
init();

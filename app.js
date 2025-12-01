// Indy YMCA Pool Times - Static Site JS

let scheduleData = null;
let selectedBranches = new Set();
let branchPicker = null;

async function init() {
  try {
    const response = await fetch('data/schedule.json');
    if (!response.ok) throw new Error('Failed to load schedule data');
    scheduleData = await response.json();

    initBranchSelector();
    renderSchedule();
    updateLastUpdated();
  } catch (error) {
    document.getElementById('schedule-container').innerHTML =
      `<p class="error">Error loading schedule: ${error.message}</p>`;
  }
}

// Check if a branch has any sessions across all days
function branchHasSessions(branch) {
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

function initBranchSelector() {
  const select = document.getElementById('branch-select');
  const branches = scheduleData.branches.sort((a, b) => a.name.localeCompare(b.name));

  // Build options - disabled branches have no sessions
  const activeBranches = branches.filter(b => branchHasSessions(b));
  const inactiveBranches = branches.filter(b => !branchHasSessions(b));

  // Add active branches as options
  activeBranches.forEach(branch => {
    const option = document.createElement('option');
    option.value = branch.key;
    option.textContent = branch.name;
    select.appendChild(option);
  });

  // Get initial selection from URL or default to all active
  const urlBranches = getBranchesFromUrl();
  let initialSelection;

  if (urlBranches) {
    // Filter to only valid active branch keys
    initialSelection = urlBranches.filter(key =>
      activeBranches.some(b => b.key === key)
    );
  } else {
    // Default: select all active branches
    initialSelection = activeBranches.map(b => b.key);
  }

  initialSelection.forEach(key => selectedBranches.add(key));

  // Initialize tom-select with checkbox options
  branchPicker = new TomSelect('#branch-select', {
    plugins: ['checkbox_options', 'remove_button'],
    items: initialSelection,
    maxOptions: null,
    placeholder: 'Select branches...',
    hideSelected: false,
    closeAfterSelect: false,
    onItemAdd: (value) => {
      selectedBranches.add(value);
      updateUrl();
      renderSchedule();
    },
    onItemRemove: (value) => {
      selectedBranches.delete(value);
      updateUrl();
      renderSchedule();
    }
  });

  // Show disabled branches info if any
  if (inactiveBranches.length > 0) {
    const disabledInfo = document.createElement('p');
    disabledInfo.className = 'disabled-branches-info';
    disabledInfo.textContent = `No lap swim times: ${inactiveBranches.map(b => b.name).join(', ')}`;
    document.getElementById('branch-selector').appendChild(disabledInfo);
  }

  // Update URL with initial selection
  updateUrl();
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
    container.innerHTML = '<p class="no-selection">Select at least one branch to view schedules</p>';
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

      html += `<div class="branch-column">`;
      html += `<h3 class="branch-name">${branch.name}</h3>`;

      if (rawSessions.length === 0) {
        html += `<p class="no-sessions">No lap swim</p>`;
      } else {
        html += `<ul class="session-list">`;
        sessions.forEach(session => {
          if (session.isClosed) {
            html += `<li class="session closed">
              <span class="time">${session.start_time} - ${session.end_time}</span>
              <span class="lanes">Closed</span>
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

// Test details toggle
function toggleTestDetails(index) {
  const details = document.getElementById(`test-details-${index}`);
  const header = details.previousElementSibling;
  const expandIcon = header.querySelector('.test-expand');
  
  if (details.style.display === 'none' || !details.style.display) {
    details.style.display = 'block';
    expandIcon.classList.add('expanded');
  } else {
    details.style.display = 'none';
    expandIcon.classList.remove('expanded');
  }
}

// Filter functionality
document.addEventListener('DOMContentLoaded', function() {
  const searchInput = document.getElementById('searchInput');
  const statusFilter = document.getElementById('statusFilter');
  const tagFilter = document.getElementById('tagFilter');
  const testCards = document.querySelectorAll('.test-card');
  
  function filterTests() {
    const searchTerm = searchInput.value.toLowerCase();
    const selectedStatus = statusFilter.value;
    const selectedTag = tagFilter.value;
    
    testCards.forEach(card => {
      const testName = card.querySelector('.test-name').textContent.toLowerCase();
      const testStatus = Array.from(card.classList).find(c => 
        ['passed', 'failed', 'skipped', 'error'].includes(c)
      );
      const testTags = Array.from(card.querySelectorAll('.test-tag')).map(
        tag => tag.textContent
      );
      
      const matchesSearch = !searchTerm || testName.includes(searchTerm);
      const matchesStatus = !selectedStatus || testStatus === selectedStatus;
      const matchesTag = !selectedTag || testTags.includes(selectedTag);
      
      card.style.display = matchesSearch && matchesStatus && matchesTag ? 'block' : 'none';
    });
    
    updateVisibleCount();
  }
  
  function updateVisibleCount() {
    const visibleCount = Array.from(testCards).filter(
      card => card.style.display !== 'none'
    ).length;
    
    const totalCount = testCards.length;
    const filterInfo = document.querySelector('.filter-info');
    
    if (filterInfo) {
      filterInfo.textContent = `Showing ${visibleCount} of ${totalCount} tests`;
    }
  }
  
  // Add event listeners
  searchInput.addEventListener('input', filterTests);
  statusFilter.addEventListener('change', filterTests);
  tagFilter.addEventListener('change', filterTests);
  
  // Keyboard shortcuts
  document.addEventListener('keydown', function(e) {
    // Ctrl/Cmd + F to focus search
    if ((e.ctrlKey || e.metaKey) && e.key === 'f') {
      e.preventDefault();
      searchInput.focus();
    }
    
    // Escape to clear filters
    if (e.key === 'Escape') {
      searchInput.value = '';
      statusFilter.value = '';
      tagFilter.value = '';
      filterTests();
    }
    
    // E to expand all, C to collapse all
    if (e.key === 'e' && !e.ctrlKey && !e.metaKey) {
      expandAll();
    } else if (e.key === 'c' && !e.ctrlKey && !e.metaKey) {
      collapseAll();
    }
  });
  
  // Expand/Collapse all
  function expandAll() {
    document.querySelectorAll('.test-details').forEach(details => {
      details.style.display = 'block';
      const expandIcon = details.previousElementSibling.querySelector('.test-expand');
      expandIcon.classList.add('expanded');
    });
  }
  
  function collapseAll() {
    document.querySelectorAll('.test-details').forEach(details => {
      details.style.display = 'none';
      const expandIcon = details.previousElementSibling.querySelector('.test-expand');
      expandIcon.classList.remove('expanded');
    });
  }
  
  // Auto-expand failed tests
  document.querySelectorAll('.test-card.failed, .test-card.error').forEach(card => {
    const index = card.getAttribute('data-test-index');
    const details = document.getElementById(`test-details-${index}`);
    if (details) {
      details.style.display = 'block';
      const expandIcon = card.querySelector('.test-expand');
      expandIcon.classList.add('expanded');
    }
  });
  
  // Theme toggle
  const themeToggle = document.createElement('button');
  themeToggle.className = 'theme-toggle';
  themeToggle.innerHTML = '🌓';
  themeToggle.style.cssText = `
    position: fixed;
    bottom: 20px;
    right: 20px;
    background: var(--bg-secondary);
    border: 1px solid var(--border-color);
    border-radius: 50%;
    width: 50px;
    height: 50px;
    font-size: 1.5rem;
    cursor: pointer;
    box-shadow: var(--shadow-md);
    transition: var(--transition);
  `;
  
  themeToggle.addEventListener('click', function() {
    const html = document.documentElement;
    const currentTheme = html.getAttribute('data-theme');
    const newTheme = currentTheme === 'dark' ? 'light' : 'dark';
    html.setAttribute('data-theme', newTheme);
    localStorage.setItem('theme', newTheme);
  });
  
  document.body.appendChild(themeToggle);
  
  // Load saved theme
  const savedTheme = localStorage.getItem('theme');
  if (savedTheme) {
    document.documentElement.setAttribute('data-theme', savedTheme);
  }
  
  // Copy code blocks on click
  document.querySelectorAll('.code-block, pre').forEach(block => {
    block.style.cursor = 'pointer';
    block.title = 'Click to copy';
    
    block.addEventListener('click', function() {
      const text = this.textContent;
      navigator.clipboard.writeText(text).then(() => {
        const originalBg = this.style.background;
        this.style.background = 'var(--color-passed)';
        this.style.color = 'white';
        
        setTimeout(() => {
          this.style.background = originalBg;
          this.style.color = '';
        }, 200);
      });
    });
  });
  
  // Add filter info
  const filterInfoDiv = document.createElement('div');
  filterInfoDiv.className = 'filter-info';
  filterInfoDiv.style.cssText = `
    margin-top: 10px;
    color: var(--text-secondary);
    font-size: 0.9rem;
  `;
  document.querySelector('.filters').appendChild(filterInfoDiv);
  
  updateVisibleCount();
});
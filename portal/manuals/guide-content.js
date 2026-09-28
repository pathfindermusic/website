// Loads a guide's editable content from a Markdown file (managed through the
// Decap CMS editor at /admin/) and renders it into the page's .doc-content
// card, then builds the "On this page" table of contents from whichever
// headings the rendered content actually contains.
//
// The existing guide text was carried over as raw HTML inside the Markdown
// file — marked() passes raw HTML straight through unchanged — so today's
// guides render exactly as they did before this change. Anything typed
// fresh in the CMS's rich-text editor becomes real Markdown and is fully
// WYSIWYG-editable there, including inserting a screenshot with the
// editor's image button (no HTML needed for new content).
//
// Shared by system-overview.html, admin-guide.html, teacher-guide.html and
// student-guide.html — this is the one deliberate exception to this
// codebase's usual "duplicate the script per page" pattern (see
// portal/README.md), because all four pages need identical fetch/render/TOC
// logic and only the .md path differs.

async function loadGuideContent(mdPath, opts = {}) {
  const contentSelector = opts.contentSelector || '.doc-content';
  const tocSelector = opts.tocSelector || '.doc-toc';

  const contentEl = document.querySelector(contentSelector);
  if (!contentEl) return;

  let raw;
  try {
    const res = await fetch(mdPath, { cache: 'no-store' });
    if (!res.ok) throw new Error(`${res.status} ${res.statusText}`);
    raw = await res.text();
  } catch (err) {
    console.error('[guide-content] Could not load', mdPath, err);
    contentEl.innerHTML = '<p>Sorry — this guide could not be loaded right now. Please refresh, or try again shortly.</p>';
    const tocEl = document.querySelector(tocSelector);
    if (tocEl) tocEl.style.display = 'none';
    return;
  }

  const { frontmatter, body } = splitFrontmatter(raw);

  if (typeof marked === 'undefined') {
    console.error('[guide-content] marked.js did not load; showing unrendered content.');
    contentEl.textContent = body;
    return;
  }

  const rendered = marked.parse(body);
  const updatedLine = frontmatter.updated
    ? `<div class="doc-updated">Last updated: ${escapeHtml(frontmatter.updated)}</div>`
    : '';
  contentEl.innerHTML = updatedLine + rendered;

  buildToc(contentEl, tocSelector);
}

function splitFrontmatter(raw) {
  const match = /^---\s*\n([\s\S]*?)\n---\s*\n?/.exec(raw);
  if (!match) return { frontmatter: {}, body: raw };
  const frontmatter = {};
  match[1].split('\n').forEach(line => {
    const kv = /^([A-Za-z0-9_]+):\s*(.*)$/.exec(line);
    if (kv) frontmatter[kv[1]] = kv[2].trim().replace(/^["']|["']$/g, '');
  });
  return { frontmatter, body: raw.slice(match[0].length) };
}

// Rebuilds the "On this page" box from whatever <h2 id="..."> / <h3 id="...">
// headings ended up in the rendered content, nesting each h3 under the h2
// that precedes it. A heading with no id (as some sub-headings intentionally
// have) is simply left out of the list, same as before this change.
function buildToc(contentEl, tocSelector) {
  const tocRoot = document.querySelector(tocSelector);
  if (!tocRoot) return;

  const headings = Array.from(contentEl.querySelectorAll('h2[id], h3[id]'));
  if (!headings.length) {
    tocRoot.style.display = 'none';
    return;
  }

  const list = document.createElement('ul');
  let currentSubList = null;

  headings.forEach(h => {
    const li = document.createElement('li');
    const a = document.createElement('a');
    a.href = `#${h.id}`;
    a.textContent = h.textContent;
    li.appendChild(a);

    if (h.tagName === 'H2') {
      list.appendChild(li);
      currentSubList = null;
    } else {
      if (!currentSubList) {
        const parentLi = list.lastElementChild;
        if (!parentLi) { list.appendChild(li); return; }
        currentSubList = document.createElement('ul');
        parentLi.appendChild(currentSubList);
      }
      currentSubList.appendChild(li);
    }
  });

  const titleEl = tocRoot.querySelector('.doc-toc-title');
  tocRoot.innerHTML = '';
  if (titleEl) {
    tocRoot.appendChild(titleEl);
  } else {
    const t = document.createElement('div');
    t.className = 'doc-toc-title';
    t.textContent = 'On this page';
    tocRoot.appendChild(t);
  }
  tocRoot.appendChild(list);
}

function escapeHtml(str) {
  return String(str).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

const TYPE_LABELS = {
    cochrane: 'Cochrane Review',
    systematicReview: 'Systematic Review',
    metaAnalysis: 'Meta-Analysis',
    rct: 'RCT',
    review: 'Review',
    guideline: 'Guideline'
};

export function buildCitationMap(citations) {
    const map = {};
    for (const citation of citations) {
        map[citation.id] = citation;
    }
    return map;
}

export function renderCitation(citation) {
    if (!citation) return '';

    return `
        <div class="citation citation-${citation.type}">
            <span class="citation-type">${TYPE_LABELS[citation.type] || citation.type}</span>
            <a href="${citation.url}" target="_blank" rel="noopener noreferrer">
                ${escapeHtml(citation.title)}
            </a>
            <span class="citation-meta">${escapeHtml(citation.source)}, ${citation.year}</span>
        </div>
    `;
}

export function renderCitations(citationIds, citationMap) {
    if (!citationIds || citationIds.length === 0) return '';

    const citations = citationIds
        .map(id => citationMap[id])
        .filter(c => c);

    if (citations.length === 0) return '';

    return `
        <div class="citations">
            ${citations.map(c => renderCitation(c)).join('')}
        </div>
    `;
}

function escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
}

// Visitor drafts stay in this element's memory; leaving the page discards them.
class TorontoRidings extends HTMLElement {
  connectedCallback() {
    if (this.listeners) return
    this.listeners = new AbortController()
    const opts = { signal: this.listeners.signal }
    const find = selector => this.querySelector(selector)
    const links = Array.from(this.querySelectorAll('a[data-slug]'))
    const search = find('input[type=search]')
    const letter = find('textarea')
    const feedback = find('[data-feedback]')
    const drafts = new Map()
    let selected

    const normalize = value => value.normalize('NFD').replace(/\p{M}/gu, '').toLowerCase().replace(/[^\p{L}\p{N}]+/gu, ' ').trim()
    const filter = () => {
      const query = normalize(search.value)
      let count = 0
      for (const link of links) {
        link.parentElement.hidden = !normalize([link.dataset.riding, link.dataset.mp || 'Seat vacant', link.dataset.formerly || ''].join(' ')).includes(query)
        if (!link.parentElement.hidden) count++
      }
      find('[data-count]').textContent = count ? count + (count === 1 ? ' riding' : ' ridings') : 'No matching riding.'
    }
    const select = (link, updateURL) => {
      if (selected?.dataset.mp) drafts.set(selected.dataset.slug, letter.value)
      selected?.removeAttribute('aria-current')
      selected = link
      link.setAttribute('aria-current', 'true')
      const {mp, riding, slug} = link.dataset
      find('[data-name]').textContent = mp || 'Seat vacant'
      find('[data-instruction]').textContent = mp ? riding : 'There is no sitting MP for ' + riding + '.'
      const contact = find('[data-contact]')
      contact.href = link.href
      contact.hidden = false
      find('[data-compose]').hidden = !mp
      letter.value = mp ? drafts.get(slug) ?? this.dataset.template.replaceAll('{mp}', mp).replaceAll('{riding}', riding) : ''
      feedback.textContent = ''
      if (updateURL) {
        const url = new URL(location.href)
        url.searchParams.set('riding', slug)
        history.replaceState(history.state, '', url)
        if (matchMedia('(max-width: 767px)').matches) find('[data-result]').focus()
      }
    }
    search.addEventListener('input', filter, opts)
    for (const link of links) link.addEventListener('click', event => {
      if (event.ctrlKey || event.metaKey || event.shiftKey || event.altKey) return
      event.preventDefault()
      select(link, true)
    }, opts)
    find('[data-copy]').addEventListener('click', async () => {
      try {
        await navigator.clipboard.writeText(letter.value)
        feedback.textContent = 'Letter copied.'
      } catch {
        letter.focus()
        letter.select()
        feedback.textContent = 'Letter selected. Press Ctrl+C or ⌘C to copy.'
      }
    }, opts)
    filter()
    const slug = new URLSearchParams(location.search).get('riding')
    const arrival = links.find(link => link.dataset.slug === slug)
    if (arrival) select(arrival, false)
  }
  disconnectedCallback() {
    this.listeners?.abort()
    this.listeners = null
  }
}
if (!customElements.get('toronto-ridings')) customElements.define('toronto-ridings', TorontoRidings)

import {learningId} from "./learning_id"
// Use the same local reading list and authenticated endpoint as the library.
export function createBookmarks(root) {
  const anonymousKey = "pauseai-ca:learning:v1"
  const account = root.dataset.accountId
  const key = account ? `${anonymousKey}:${account}` : anonymousKey
  let persistent = true, state = {ids: []}, pending = Promise.resolve()
  const readKey = key => {try {return JSON.parse(localStorage.getItem(key) || "{}")} catch (_) {persistent = false; return {}}}
  state = {...state, ...readKey(key)}
  if (!Array.isArray(state.ids)) state.ids = []
  state.pending = Array.isArray(state.pending) ? state.pending : []
  if (account) {
    state.ids = [...new Set([...JSON.parse(root.dataset.account), ...state.ids,
      ...(state.transferred === account ? [] : readKey(anonymousKey).ids || [])])]
    for (const change of state.pending) state.ids = change.operation === "remove" ? state.ids.filter(id=>id!==change.id) : [...new Set([...state.ids,...(change.ids||[]),...(change.id?[change.id]:[])])]
    state.transferred = account
  }
  const save = () => {try {localStorage.setItem(key, JSON.stringify(state))} catch (_) {persistent = false}}
  const send = change => {
    pending = pending.catch(() => {}).then(async () => {
      const response = await fetch('/learning/basket', {method:'POST',keepalive:true,headers:{'content-type':'application/json','x-csrf-token':document.querySelector('meta[name=csrf-token]').content},body:JSON.stringify(change)})
      if (!response.ok) throw Error('save')
      state.pending = state.pending.filter(item=>item.token!==change.token); save()
    }).catch(() => {
      const status = document.getElementById('bookmark-status')
      if (status) status.textContent = JSON.parse(root.dataset.copy)['Account sync failed. Your bookmarks remain in this browser; try again when connected.']
    })
  }
  const sync = (operation, id) => {
    if (!account) return
    const change = {operation, id, ids: [...state.ids], token: learningId()}
    state.pending.push(change); save(); send(change)
  }
  save(); if (account) {state.pending.forEach(send);sync('merge')}
  window.addEventListener('online',()=>{if(account)state.pending.forEach(send)})
  return {
    read: () => [...state.ids], isPersistent: () => persistent,
    toggle(id) { const selected = state.ids.includes(id); state.ids = selected ? state.ids.filter(x => x !== id) : [...state.ids,id]; save(); sync(selected?'remove':'add',id); return !selected },
    registrationURL() {return '/users/register?'+new URLSearchParams({from:'resource_bookmark',locale:root.dataset.locale,basket:state.ids.join(','),return_to:root.dataset.locale==='fr'?'/fr/comprendre':'/en/learn'})},
    icon: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" aria-hidden="true"><path stroke-linecap="round" stroke-linejoin="round" d="M17.593 3.322c1.1.128 1.907 1.077 1.907 2.185V21l-7.5-3.75L4.5 21V5.507c0-1.108.806-2.057 1.907-2.185a48.507 48.507 0 0111.186 0z"/></svg>'
  }
}

// Sharing uses browser APIs only. No third-party sharing scripts or destination tracking.
export function gameShareURL(locale) {
  const url = new URL(locale === 'fr' ? '/fr/agent-rebelle' : '/en/rogue-agent', location.origin)
  url.search = new URLSearchParams({utm_source:'game_share',utm_medium:'referral',utm_campaign:'rogue_agent_popup'})
  return url.href
}

export function leaveGameWindow(event, href) {
  if (event.button !== 0 || event.ctrlKey || event.metaKey || event.shiftKey || event.altKey) return
  let opener
  try {if(window.opener && !window.opener.closed && window.opener.location.origin === location.origin) opener=window.opener} catch (_) {}
  if (opener) {
    event.preventDefault()
    opener.location.assign(href)
    opener.focus()
    window.close()
  } else if (window.name === 'pauseai-rogue-game') {
    // The review opener may be on another origin, or the original tab may be closed.
    const page=window.open(href,'_blank')
    if(page){event.preventDefault();page.opener=null;page.focus();window.close()}
  }
  // A game opened as an ordinary tab retains normal same-tab navigation.
}

export function setupGameSharing(root,t) {
  const button=root.querySelector('#share-game'), panel=root.querySelector('#game-share-panel')
  const input=root.querySelector('#game-share-url'),status=root.querySelector('#game-share-status')
  input.value=gameShareURL(root.dataset.locale)
  async function copyLink(){
    let copied=false
    try {if(navigator.clipboard?.writeText){await navigator.clipboard.writeText(input.value);copied=true}}catch(_){}
    if(!copied){
      const field=document.createElement('textarea')
      field.value=input.value;field.setAttribute('aria-hidden','true');field.tabIndex=-1
      Object.assign(field.style,{position:'fixed',left:'-9999px',top:'0',opacity:'0'})
      document.body.append(field);field.select()
      try{copied=document.execCommand('copy')}catch(_){}
      field.remove()
    }
    panel.hidden=copied
    status.textContent=copied?t('Copied!'):t('Select and copy the link above.')
    if(copied){button.focus();window.getSelection()?.removeAllRanges()}
    else input.focus()
  }
  button.addEventListener('click',async()=>{
    status.textContent=''
    if(navigator.share){
      try {await navigator.share({title:t('Rogue agent · game'),text:t('Can you close this rogue agent?'),url:input.value});return}
      catch(error){if(error.name==='AbortError')return}
    }
    await copyLink()
  })
  root.querySelector('#copy-game-link').addEventListener('click',copyLink)
  root.querySelector('#close-game-share').addEventListener('click',()=>{panel.hidden=true;button.focus()})
  panel.addEventListener('keydown',event=>{if(event.key==='Escape'){event.preventDefault();event.stopPropagation();panel.hidden=true;button.focus()}})
}

// Both desktop and mobile Learn menus launch the same game window on request.
document.addEventListener('click',event=>{
  const link=event.target.closest('a[data-rogue-launch="true"]')
  if(!link || event.button!==0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey)return
  const game=window.open(link.href,'pauseai-rogue-game','popup,width=820,height=850')
  if(game){event.preventDefault();game.focus()}
})

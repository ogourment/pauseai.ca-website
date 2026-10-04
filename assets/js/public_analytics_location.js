export function publicAnalyticsLocation() {
  const url=new URL(location.origin+location.pathname)
  const query=new URLSearchParams(location.search)
  if(query.get('utm_source')==='game_share' && query.get('utm_medium')==='referral' && query.get('utm_campaign')==='rogue_agent_popup'){
    url.search=new URLSearchParams({utm_source:'game_share',utm_medium:'referral',utm_campaign:'rogue_agent_popup'})
  }
  return url.href
}

import { useEffect, useMemo, useState } from 'react'
import {
  Activity, ArrowRight, Bell, Building2, CalendarDays, Check, CheckCircle2,
  ChevronDown, ChevronRight, CircleAlert, Clock3, Coffee, DoorOpen, FileCheck2,
  FileText, Gauge, LayoutDashboard, LogOut, Plus, Search, ShieldCheck, Ticket,
  UserCheck, UserRound, Users, WalletCards, X, Zap, Timer, ClipboardList,
} from 'lucide-react'
import { isLiveConfigured, supabase } from './lib/supabase'

const STORE = 'offline-demo-v1'
const ACTIVE = ['booked', 'arrived', 'serving']
const isoDay = d => [d.getFullYear(), String(d.getMonth()+1).padStart(2,'0'), String(d.getDate()).padStart(2,'0')].join('-')
const plusDays = (d,n) => { const x=new Date(d); x.setDate(x.getDate()+n); return x }
const weekdays = (n=6) => { const out=[]; let d=new Date(); while(out.length<n){d=plusDays(d,1);if(d.getDay()!==0&&d.getDay()!==6)out.push(d)} return out }
const time = s => new Date(s).toLocaleTimeString('en-IN',{hour:'numeric',minute:'2-digit'})
const dateLabel = s => new Date(s+'T12:00:00').toLocaleDateString('en-IN',{weekday:'short',day:'numeric',month:'short'})
const dateTime = s => new Date(s).toLocaleString('en-IN',{weekday:'short',day:'numeric',month:'short',hour:'numeric',minute:'2-digit'})
const uid = () => Math.random().toString(36).slice(2,9)+Date.now().toString(36)
const seed = () => {
  const dates=weekdays(6), day=isoDay(dates[0])
  const works=[
    {id:'w1',name:'Bonafide Certificate',description:'Request and collect a bonafide certificate.',avg_service_minutes:10,active:true},
    {id:'w2',name:'Document Verification',description:'Verification of college forms and documents.',avg_service_minutes:8,active:true},
    {id:'w3',name:'ID Card Services',description:'New, replacement and correction requests.',avg_service_minutes:12,active:true},
    {id:'w4',name:'Fee & Accounts',description:'Fee receipts, dues and account queries.',avg_service_minutes:10,active:true},
  ]
  const windows=[
    {id:'c1',work_id:'w1',name:'Window 01 · Student Services',location:'Administrative Block',status:'open'},
    {id:'c2',work_id:'w2',name:'Window 02 · Verification',location:'Administrative Block',status:'open'},
    {id:'c3',work_id:'w3',name:'Window 03 · ID Desk',location:'Ground Floor',status:'open'},
    {id:'c4',work_id:'w4',name:'Window 04 · Accounts',location:'Administrative Block',status:'break'},
  ]
  const slots=[]
  dates.forEach(d=>windows.forEach(win=>[9,10,11,13,14,15,16].forEach(h=>{
    const a=new Date(d);a.setHours(h,0,0,0)
    const b=new Date(d);b.setHours(h+1,0,0,0)
    const dur=works.find(w=>w.id===win.work_id).avg_service_minutes
    slots.push({id:win.id+'-'+isoDay(d)+'-'+h,window_id:win.id,slot_date:isoDay(d),starts_at:a.toISOString(),ends_at:b.toISOString(),capacity:Math.max(1,Math.floor(45/dur)),buffer_minutes:15})
  })))
  const mk=(id,sl,win,num,name,status,student='u-x')=>({id,slot_id:sl.id,window_id:win,token_number:num,queue_position:num,student_id:student,student_name:name,status,booked_at:new Date().toISOString(),arrived_at:status==='arrived'?new Date().toISOString():null,slot:sl})
  const first=slots.find(s=>s.window_id==='c1'&&s.slot_date===day&&new Date(s.starts_at).getHours()===9)
  const second=slots.find(s=>s.window_id==='c1'&&s.slot_date===day&&new Date(s.starts_at).getHours()===10)
  const other=slots.find(s=>s.window_id==='c2'&&s.slot_date===day)
  return {
    works,windows,slots,
    tokens:[mk('t1',first,'c1',1,'Aarav Sharma','arrived','u-a'),mk('t2',first,'c1',2,'Riya Kapoor','booked','u-r'),mk('t3',second,'c1',3,'You · SANS','booked','u-me'),mk('t4',other,'c2',1,'Kabir Sethi','completed','u-k')],
    breaks:[{id:'b1',window_id:'c4',reason:'Short staff handover',status:'pending',requested_by:'Staff member'}],
    currentUser:{id:'u-me',full_name:'SANS',role:'student',college_id:'245703441'}
  }
}
const getDemo = () => { try { return JSON.parse(localStorage.getItem(STORE)) || seed() } catch { return seed() } }
const Btn = ({children,kind='primary',size='',...props}) => <button className={'btn btn-'+kind+' '+size} {...props}>{children}</button>
const Bubble = ({children,tone=''}) => <span className={'bubble '+tone}>{children}</span>
const Badge = ({value}) => <span className={'badge badge-'+value}>{({booked:'Booked',arrived:'Arrived',serving:'In service',completed:'Completed',cancelled:'Cancelled'})[value]||value}</span>
const Metric = ({label,value,hint,icon}) => <div className="metric"><div className="metric-top"><span>{label}</span><Bubble>{icon}</Bubble></div><strong>{value}</strong><small>{hint}</small></div>

export default function App(){
  const [data,setData]=useState(getDemo)
  const [role,setRole]=useState('student')
  const [page,setPage]=useState('overview')
  const [toast,setToast]=useState('')
  const [modal,setModal]=useState('')
  const [workId,setWorkId]=useState('w1')
  const [windowId,setWindowId]=useState('c1')
  const [day,setDay]=useState(()=>isoDay(weekdays(1)[0]))
  const [slotId,setSlotId]=useState('')
  const [query,setQuery]=useState('')
  const [newWork,setNewWork]=useState({name:'',description:'',duration:10})
  const [newWindow,setNewWindow]=useState({name:'',work_id:'w1',location:'Administrative Block'})
  const [auth,setAuth]=useState(null)
  const [profile,setProfile]=useState(null)
  const [authMode,setAuthMode]=useState('signin')
  const [authForm,setAuthForm]=useState({email:'',password:'',full_name:'',college_id:''})
  const [loading,setLoading]=useState(false)
  const [error,setError]=useState('')

  const live=Boolean(isLiveConfigured&&auth?.user&&profile)
  const user=profile||data.currentUser
  const works=data.works||[], windows=data.windows||[], slots=data.slots||[], tokens=data.tokens||[]
  const nextDays=weekdays(6)
  const selectedWork=works.find(w=>w.id===workId)
  const selectedWindow=windows.find(w=>w.id===windowId)
  const serviceWindows=windows.filter(w=>w.work_id===workId)
  const ownTokens=tokens.filter(t=>live?t.student_id===user?.id:t.student_id==='u-me')
  const queue=tokens.filter(t=>t.window_id===windowId&&ACTIVE.includes(t.status)).sort((a,b)=>{
    const rank={serving:0,arrived:1,booked:2}
    return rank[a.status]-rank[b.status] || new Date(a.arrived_at||a.booked_at)-new Date(b.arrived_at||b.booked_at)
  })
  const options=slots.filter(s=>s.window_id===windowId&&s.slot_date===day).map(s=>({
    ...s,used:tokens.filter(t=>t.slot_id===s.id&&ACTIVE.includes(t.status)).length
  })).filter(s=>new Date(s.starts_at)>new Date()&&s.used<s.capacity).sort((a,b)=>new Date(a.starts_at)-new Date(b.starts_at))
  const openWindows=windows.filter(w=>w.status==='open').length
  const completed=tokens.filter(t=>t.status==='completed').length
  const pending=(data.breaks||[]).filter(b=>b.status==='pending')

  useEffect(()=>{ if(!live) localStorage.setItem(STORE,JSON.stringify(data)) },[data,live])
  useEffect(()=>{
    if(!isLiveConfigured)return
    let mounted=true
    const init=async()=>{
      setLoading(true)
      const {data:r}=await supabase.auth.getSession()
      if(mounted&&r.session){setAuth(r.session);await loadLive(r.session.user)}
      if(mounted)setLoading(false)
    }
    init()
    const {data:sub}=supabase.auth.onAuthStateChange(async(_event,session)=>{
      if(!mounted)return
      setAuth(session)
      if(session?.user)await loadLive(session.user)
      else setProfile(null)
    })
    return()=>{mounted=false;sub.subscription.unsubscribe()}
  },[])
  async function loadLive(u){
    setLoading(true);setError('')
    try{
      const [p,w,ws,sl,t,b]=await Promise.all([
        supabase.from('offline_profiles').select('*').eq('id',u.id).single(),
        supabase.from('offline_works').select('*').order('name'),
        supabase.from('offline_windows').select('*').order('name'),
        supabase.from('offline_slots').select('*').gte('slot_date',isoDay(new Date())).order('starts_at').limit(500),
        supabase.from('offline_tokens').select('*,slot:slots(*)').order('booked_at',{ascending:false}).limit(300),
        supabase.from('offline_break_requests').select('*').order('requested_at',{ascending:false}).limit(50),
      ])
      const failure=[p,w,ws,sl,t,b].find(x=>x.error)
      if(failure)throw failure.error
      setProfile(p.data)
      setData(prev=>({...prev,works:w.data,windows:ws.data,slots:sl.data,tokens:t.data.map(x=>({...x,student_name:x.student_id===u.id?'You':'Student '+x.token_number})),breaks:b.data}))
      setRole(p.data.role);setWorkId(w.data[0]?.id||'');setWindowId(ws.data[0]?.id||'')
    }catch(e){setError(e.message||'Could not load your workspace.')}
    finally{setLoading(false)}
  }
  function notify(s){setToast(s);clearTimeout(notify.timer);notify.timer=setTimeout(()=>setToast(''),3000)}
  async function submitAuth(e){
    e.preventDefault();setLoading(true);setError('')
    try{
      const args=authMode==='signup'
        ?{email:authForm.email,password:authForm.password,options:{data:{full_name:authForm.full_name,college_id:authForm.college_id}}}
        :{email:authForm.email,password:authForm.password}
      const {data:r,error:e2}=authMode==='signup'?await supabase.auth.signUp(args):await supabase.auth.signInWithPassword(args)
      if(e2)throw e2
      if(authMode==='signup'&&!r.session)notify('Account created. Confirm your email, then sign in.')
    }catch(e2){setError(e2.message||'Authentication failed.')}
    finally{setLoading(false)}
  }
  async function logout(){await supabase.auth.signOut();setAuth(null);setProfile(null)}
  function changeRole(next){setRole(next);setPage('overview');const w=windows.find(x=>x.status==='open')||windows[0];if(w)setWindowId(w.id)}
  async function book(){
    if(!slotId)return notify('Choose an available slot first.')
    if(selectedWindow?.status!=='open')return notify('This service window is unavailable.')
    if(live){
      const {error:e}=await supabase.rpc('offline_book_token',{p_slot_id:slotId})
      if(e)return notify(e.message)
      await loadLive(auth.user)
    }else{
      const s=slots.find(x=>x.id===slotId)
      const count=tokens.filter(t=>t.slot_id===slotId&&ACTIVE.includes(t.status)).length
      const same=tokens.filter(t=>t.window_id===s.window_id&&t.slot?.slot_date===s.slot_date)
      const num=Math.max(0,...same.map(t=>t.token_number||0))+1
      const token={id:uid(),slot_id:s.id,window_id:s.window_id,student_id:'u-me',student_name:'You · SANS',token_number:num,queue_position:count+1,status:'booked',booked_at:new Date().toISOString(),slot:s}
      setData(d=>({...d,tokens:[...d.tokens,token]}))
    }
    setSlotId('');setPage('tokens');notify('Your token has been booked.')
  }
  async function cancelOwn(t){
    if(live){const {error:e}=await supabase.rpc('offline_cancel_own_token',{p_token_id:t.id});if(e)return notify(e.message);await loadLive(auth.user)}
    else setData(d=>({...d,tokens:d.tokens.map(x=>x.id===t.id?{...x,status:'cancelled',cancellation_type:'student'}:x)}))
    notify('Token cancelled. Existing token numbers remain unchanged.')
  }
  async function staffAction(t,action){
    if(live){const {error:e}=await supabase.rpc('offline_staff_update_token',{p_token_id:t.id,p_action:action,p_reason:action==='cancel'?'Late / no-show':null});if(e)return notify(e.message);await loadLive(auth.user)}
    else{
      const next={arrive:'arrived',start:'serving',complete:'completed',cancel:'cancelled'}[action]
      setData(d=>({...d,tokens:d.tokens.map(x=>x.id===t.id?{
        ...x,status:next,arrived_at:action==='arrive'?new Date().toISOString():x.arrived_at,
        service_started_at:action==='start'?new Date().toISOString():x.service_started_at,
        completed_at:action==='complete'?new Date().toISOString():x.completed_at,
        cancellation_type:action==='cancel'?'staff':x.cancellation_type,
      }:x)}))
    }
    notify(({arrive:'Arrival recorded.',start:'Student called to the counter.',complete:'Service marked complete.',cancel:'Token cancelled.'})[action])
  }
  async function toggleWindow(w){
    const next=w.status==='open'?'closed':'open'
    if(live){const {error:e}=await supabase.from('offline_windows').update({status:next}).eq('id',w.id);if(e)return notify(e.message);await loadLive(auth.user)}
    else setData(d=>({...d,windows:d.windows.map(x=>x.id===w.id?{...x,status:next}:x)}))
    notify('Window '+next+'.')
  }
  async function saveWork(e){
    e.preventDefault()
    if(live){const {error:e2}=await supabase.from('offline_works').insert({name:newWork.name,description:newWork.description,avg_service_minutes:Number(newWork.duration)});if(e2)return notify(e2.message);await loadLive(auth.user)}
    else setData(d=>({...d,works:[...d.works,{...newWork,id:uid(),avg_service_minutes:Number(newWork.duration),active:true}]}))
    setNewWork({name:'',description:'',duration:10});setModal('');notify('Service added.')
  }
  async function saveWindow(e){
    e.preventDefault()
    if(live){const {error:e2}=await supabase.from('offline_windows').insert({...newWindow,status:'open'});if(e2)return notify(e2.message);await loadLive(auth.user)}
    else setData(d=>({...d,windows:[...d.windows,{...newWindow,id:uid(),status:'open'}]}))
    setNewWindow({name:'',work_id:works[0]?.id||'',location:'Administrative Block'});setModal('');notify('Window added.')
  }
  async function reviewBreak(item,status){
    if(live){const {error:e}=await supabase.from('offline_break_requests').update({status,reviewed_by:user.id,reviewed_at:new Date().toISOString()}).eq('id',item.id);if(e)return notify(e.message);await loadLive(auth.user)}
    else{
      setData(d=>({...d,breaks:d.breaks.map(b=>b.id===item.id?{...b,status}:b),windows:status==='approved'?d.windows.map(w=>w.id===item.window_id?{...w,status:'break'}:w):d.windows}))
    }
    notify('Break request '+status+'.')
  }

  const nav=role==='student'
    ?[{id:'overview',label:'Overview',icon:LayoutDashboard},{id:'book',label:'Book a token',icon:Plus},{id:'tokens',label:'My tokens',icon:Ticket}]
    :role==='staff'
    ?[{id:'overview',label:'Overview',icon:LayoutDashboard},{id:'queue',label:'Live queue',icon:Users},{id:'windows',label:'Window status',icon:DoorOpen}]
    :[{id:'overview',label:'Overview',icon:LayoutDashboard},{id:'services',label:'Services & windows',icon:Building2},{id:'analytics',label:'Analytics',icon:Activity}]
  const title=nav.find(x=>x.id===page)?.label||'Overview'
  const me=user?.full_name||'SANS'
  const today=new Date().toLocaleDateString('en-IN',{weekday:'long',day:'numeric',month:'long'})

  if(isLiveConfigured&&!auth?.user)return <div className="auth-shell"><div className="auth-card">
    <div className="brand-mark">O<span>.</span></div><p className="eyebrow">CAMPUS SERVICES, REIMAGINED</p>
    <h1>{authMode==='signup'?'Create your account.':'Welcome back.'}</h1><p className="muted">Sign in to OffLine and keep your campus errands moving.</p>
    <form onSubmit={submitAuth} className="form-stack">
      {authMode==='signup'&&<><label>Full name<input required value={authForm.full_name} onChange={e=>setAuthForm({...authForm,full_name:e.target.value})}/></label><label>College ID<input required value={authForm.college_id} onChange={e=>setAuthForm({...authForm,college_id:e.target.value})}/></label></>}
      <label>Email address<input type="email" required value={authForm.email} onChange={e=>setAuthForm({...authForm,email:e.target.value})}/></label>
      <label>Password<input type="password" required minLength="6" value={authForm.password} onChange={e=>setAuthForm({...authForm,password:e.target.value})}/></label>
      {error&&<div className="error-box">{error}</div>}
      <Btn disabled={loading}>{loading?'Please wait…':authMode==='signup'?'Create account':'Sign in'} <ArrowRight size={16}/></Btn>
    </form>
    <button className="text-button" onClick={()=>setAuthMode(authMode==='signup'?'signin':'signup')}>{authMode==='signup'?'Already have an account? Sign in':'New here? Create a student account'}</button>
    <div className="auth-foot"><ShieldCheck size={15}/> Secure access powered by Supabase</div>
  </div></div>

  return <div className="app-shell">
    <aside className="sidebar">
      <div className="brand"><div className="brand-mark">O<span>.</span></div><div><b>OffLine</b><small>Campus, without the queue.</small></div></div>
      <p className="side-label">WORKSPACE</p>
      <div className="role-card"><div className="role-avatar">{role==='student'?<UserRound/>:role==='staff'?<UserCheck/>:<ShieldCheck/>}</div><div className="role-copy"><small>Signed in as</small><b>{role==='student'?'Student':role==='staff'?'Staff member':'Administrator'}</b></div>
        {!live?<select aria-label="Switch demo role" value={role} onChange={e=>changeRole(e.target.value)}><option value="student">Student</option><option value="staff">Staff</option><option value="admin">Admin</option></select>:<ChevronDown size={15}/>}
      </div>
      <p className="side-label menu-label">MENU</p>
      <nav>{nav.map(item=><button key={item.id} className={'nav-item '+(page===item.id?'active':'')} onClick={()=>setPage(item.id)}><item.icon size={18}/><span>{item.label}</span>{page===item.id&&<i/>}</button>)}</nav>
      <div className="sidebar-end">
        <div className="help-card"><CircleAlert size={18}/><b>Need a hand?</b><p>Campus services, minus the confusion.</p><button onClick={()=>notify('Ask your campus administration for support.')}>Get support <ArrowRight size={13}/></button></div>
        <div className="side-profile"><div className="profile-avatar">{me.slice(0,1)}</div><div><b>{me}</b><small>{user?.college_id||'Campus member'}</small></div>{live?<button className="icon-btn" onClick={logout} title="Sign out"><LogOut size={16}/></button>:<span className="demo-tag">DEMO</span>}</div>
      </div>
    </aside>

    <main className="main">
      <header className="topbar"><div className="crumb"><span>Workspace</span><ChevronRight size={14}/><b>{title}</b></div><div className="top-right"><span className="today"><CalendarDays size={15}/> {today}</span><button className="icon-btn" onClick={()=>notify('You are all caught up.')}><Bell size={18}/><i/></button><div className="top-avatar">{me.slice(0,1)}</div></div></header>
      <div className="page">
        <div className="page-title"><div><p className="eyebrow">{role==='student'?'YOUR CAMPUS, ON YOUR TIME':role==='staff'?'SERVICE OPERATIONS':'CAMPUS CONTROL CENTRE'}</p>
          <h1>{page==='overview'?(role==='student'?'Good day, '+me.split(' ')[0]+'.':role==='staff'?'Your counter, at a glance.':'Everything in its place.'):page==='book'?'Book a service.':page==='tokens'?'Your tokens.':page==='queue'?'The live queue.':page==='windows'?'Window operations.':page==='services'?'Services & windows.':'The numbers that matter.'}</h1>
          <p>{page==='overview'&&role==='student'?'A little less waiting. A lot more living.':page==='overview'&&role==='staff'?'Keep the line moving. We’ll keep the numbers straight.':page==='overview'&&role==='admin'?'A clear view of how campus services are moving today.':page==='book'?'Choose what you need. We’ll take care of your place in line.':page==='tokens'?'Every booking, every update, all in one place.':page==='queue'?'Manage arrivals and serve students in the order they arrive.':page==='windows'?'Keep students informed about counter availability.':page==='services'?'Configure the services students can book.':'A quick pulse check on campus service performance.'}</p></div>
          <span className={live?'live-tag':'demo-tag-large'}><i/> {live?'Connected to Supabase':'Interactive demo mode'}</span>
        </div>
        {error&&<div className="inline-error"><CircleAlert size={16}/>{error}</div>}

        {page==='overview'&&role==='student'&&<StudentHome data={data} tokens={ownTokens} onBook={()=>setPage('book')} onTokens={()=>setPage('tokens')}/>}
        {page==='overview'&&role==='staff'&&<StaffHome queue={queue} windows={windows} windowId={windowId} setWindowId={setWindowId} onAction={staffAction} onQueue={()=>setPage('queue')} completed={completed}/>}
        {page==='overview'&&role==='admin'&&<AdminHome data={data} pending={pending} onServices={()=>setPage('services')} onReview={reviewBreak}/>}
        {page==='book'&&role==='student'&&<section className="booking-layout"><div className="booking-main">
          <section className="card"><SectionTitle n="01" title="What do you need done?" sub="Choose a campus service to get started."/>
            <div className="service-grid">{works.filter(w=>w.active!==false).map((w,i)=><button key={w.id} className={'service-choice '+(workId===w.id?'chosen':'')} onClick={()=>{setWorkId(w.id);const next=windows.find(x=>x.work_id===w.id);setWindowId(next?.id||'');setSlotId('')}}>
              <Bubble tone={['','blue','purple','orange'][i%4]}>{i===0?<FileText/>:i===1?<FileCheck2/>:i===2?<WalletCards/>:<ClipboardList/>}</Bubble><span><b>{w.name}</b><small>{w.description||'Campus service'}</small></span>{workId===w.id?<CheckCircle2 className="chosen-check"/>:<ChevronRight className="subtle"/>}
            </button>)}</div>
          </section>
          <section className="card"><SectionTitle n="02" title="Pick a service window" sub="Choose where you want to be served."/>
            <div className="window-options">{serviceWindows.map(w=><button key={w.id} className={'window-choice '+(windowId===w.id?'chosen':'')} onClick={()=>{setWindowId(w.id);setSlotId('')}}>
              <span><b>{w.name}</b><small><Building2 size={13}/> {w.location}</small></span><span className={'window-state '+w.status}>● {w.status==='open'?'Open':w.status==='break'?'On break':'Closed'}</span>
            </button>)}</div>
          </section>
          <section className="card"><SectionTitle n="03" title="When works for you?" sub="One-hour slots. The final 15 minutes are reserved for overrun."/>
            <div className="date-strip">{nextDays.map(d=><button key={isoDay(d)} className={'date-choice '+(day===isoDay(d)?'chosen':'')} onClick={()=>{setDay(isoDay(d));setSlotId('')}}><small>{d.toLocaleDateString('en-IN',{weekday:'short'})}</small><b>{d.getDate()}</b><small>{d.toLocaleDateString('en-IN',{month:'short'})}</small></button>)}</div>
            <div className="slot-grid">{options.length?options.map(s=><button key={s.id} className={'slot-choice '+(slotId===s.id?'chosen':'')} onClick={()=>setSlotId(s.id)}><b>{time(s.starts_at)}</b><small>{s.capacity-s.used} spots left</small></button>):<div className="no-slots"><Clock3/><b>No slots available</b><span>Try a different date or service window.</span></div>}</div>
            <div className="lunch-note"><Coffee size={14}/> Lunch break: 12:00 PM – 1:00 PM · No bookings during this hour</div>
          </section>
        </div><aside className="booking-summary"><p className="eyebrow">YOUR BOOKING</p><h3>Almost there.</h3><p className="muted">Review your selection before confirming.</p>
          <Summary label="Service" value={selectedWork?.name||'—'}/><Summary label="Window" value={selectedWindow?.name||'—'}/><Summary label="Date" value={dateLabel(day)}/><Summary label="Time slot" value={slotId?time(slots.find(s=>s.id===slotId)?.starts_at):'Choose a slot'}/>
          <div className="summary-info"><Timer size={17}/><span><b>Smart ETA</b><small>Your turn estimate updates as the queue moves.</small></span></div>
          <Btn disabled={!slotId||selectedWindow?.status!=='open'} onClick={book}>Confirm booking <ArrowRight size={16}/></Btn><p className="summary-foot"><ShieldCheck size={13}/> No payment required. Cancel anytime before service.</p>
        </aside></section>}
        {page==='tokens'&&role==='student'&&<TokenList tokens={ownTokens} windows={windows} onCancel={cancelOwn} onBook={()=>setPage('book')}/>}
        {page==='queue'&&role==='staff'&&<QueuePage queue={queue} windows={windows} windowId={windowId} setWindowId={setWindowId} onAction={staffAction}/>}
        {page==='windows'&&role==='staff'&&<WindowPage windows={windows} onToggle={toggleWindow}/>}
        {page==='services'&&role==='admin'&&<AdminServices data={data} query={query} setQuery={setQuery} onAddWork={()=>setModal('work')} onAddWindow={()=>setModal('window')} onToggle={toggleWindow} pending={pending} onReview={reviewBreak}/>}
        {page==='analytics'&&role==='admin'&&<Analytics data={data}/>}
      </div>
      <footer className="page-footer"><span>© 2026 OffLine · Built for better campus days.</span><span><i/> All systems operational</span></footer>
    </main>

    {modal&&<div className="modal-backdrop" onClick={()=>setModal('')}><div className="modal" onClick={e=>e.stopPropagation()}><div className="modal-head"><div><p className="eyebrow">ADMINISTRATION</p><h2>{modal==='work'?'Add a service':'Add a service window'}</h2></div><button className="icon-btn" onClick={()=>setModal('')}><X size={18}/></button></div>
      <form className="form-stack" onSubmit={modal==='work'?saveWork:saveWindow}>
        {modal==='work'?<><label>Service name<input required value={newWork.name} onChange={e=>setNewWork({...newWork,name:e.target.value})} placeholder="e.g. Library Clearance"/></label><label>Description<input value={newWork.description} onChange={e=>setNewWork({...newWork,description:e.target.value})} placeholder="What is this service for?"/></label><label>Average service time (minutes)<input type="number" min="1" max="45" value={newWork.duration} onChange={e=>setNewWork({...newWork,duration:e.target.value})}/></label></>:<><label>Window name<input required value={newWindow.name} onChange={e=>setNewWindow({...newWindow,name:e.target.value})} placeholder="e.g. Window 05 · Library"/></label><label>Service<select value={newWindow.work_id} onChange={e=>setNewWindow({...newWindow,work_id:e.target.value})}>{works.map(w=><option key={w.id} value={w.id}>{w.name}</option>)}</select></label><label>Location<input value={newWindow.location} onChange={e=>setNewWindow({...newWindow,location:e.target.value})}/></label></>}
        <div className="modal-actions"><Btn kind="ghost" type="button" onClick={()=>setModal('')}>Cancel</Btn><Btn type="submit"><Plus size={15}/> Save changes</Btn></div>
      </form>
    </div></div>}
    {toast&&<div className="toast"><CheckCircle2 size={17}/>{toast}</div>}
  </div>
}

function SectionTitle({n,title,sub}){return <div className="section-title"><span>{n}</span><div><h3>{title}</h3><p>{sub}</p></div></div>}
function Summary({label,value}){return <div className="summary-row"><small>{label}</small><b>{value}</b></div>}
function Eta({token,window}){const duration=window?.avg_service_minutes||10;const d=new Date(token.slot?.starts_at||token.booked_at);d.setMinutes(d.getMinutes()+Math.max(0,(token.queue_position||1)-1)*duration);return time(d.toISOString())}
function NextToken({token,windows}){const win=windows.find(w=>w.id===token.window_id);return <div className="next-token"><div className="token-number"><small>YOUR TOKEN NUMBER</small><strong>#{String(token.token_number).padStart(2,'0')}</strong><Badge value={token.status}/></div><div className="token-meta"><div><small>Service window</small><b>{win?.name||'Campus counter'}</b></div><div><small>Appointment</small><b>{dateTime(token.slot?.starts_at||token.booked_at)}</b></div><div><small>Estimated turn</small><b>{token.status==='arrived'?'You are checked in':token.status==='serving'?'At the counter now':<Eta token={token} window={win}/>}</b></div></div></div>}
function StudentHome({data,tokens,onBook,onTokens}){
  const next=tokens.filter(t=>ACTIVE.includes(t.status)).sort((a,b)=>new Date(a.slot?.starts_at||0)-new Date(b.slot?.starts_at||0))[0]
  return <><section className="hero"><div className="hero-text"><span className="hero-kicker"><Zap size={13}/> TIME IS YOURS AGAIN</span><h2>Do the work.<br/><em>Skip the wait.</em></h2><p>Reserve your spot at a campus counter, track your turn, and spend less time standing in line.</p><Btn onClick={onBook}>Book a token <ArrowRight size={16}/></Btn></div><div className="hero-art"><div className="orbit one"/><div className="orbit two"/><div className="ticket-art"><div>OFFLINE PASS <Ticket size={18}/></div><strong>08<span>.</span>24</strong><hr/><small>YOUR TURN, YOUR TIME</small></div><div className="float-pill"><CheckCircle2 size={15}/> No queue. No rush.</div></div></section>
    <div className="metric-grid"><Metric label="Active tokens" value={String(tokens.filter(t=>ACTIVE.includes(t.status)).length).padStart(2,'0')} hint="Your upcoming bookings" icon={<Ticket/>}/><Metric label="Open service windows" value={String(data.windows.filter(w=>w.status==='open').length).padStart(2,'0')} hint="Ready to serve" icon={<DoorOpen/>}/><Metric label="Services available" value={String(data.works.filter(w=>w.active!==false).length).padStart(2,'0')} hint="Across campus" icon={<Building2/>}/></div>
    <div className="content-grid"><div className="panel"><PanelHead title="Your next token" sub="Keep an eye on your upcoming turn." action="View all" onAction={onTokens}/>{next?<NextToken token={next} windows={data.windows}/>:<Empty icon={<Ticket/>} title="No upcoming tokens" text="Book a service and your token will appear here." action="Book a token" onClick={onBook}/>}</div>
      <div className="panel"><PanelHead title="Popular services" sub="Quick access to campus essentials."/>{data.works.slice(0,4).map((w,i)=><div className="shortcut" key={w.id}><Bubble tone={['','blue','purple','orange'][i]}>{i===0?<FileText/>:i===1?<FileCheck2/>:i===2?<WalletCards/>:<ClipboardList/>}</Bubble><span><b>{w.name}</b><small>{w.avg_service_minutes} min · Avg. service</small></span><ChevronRight className="subtle"/></div>)}</div>
    </div></>
}
function PanelHead({title,sub,action,onAction}){return <div className="panel-head"><div><h3>{title}</h3><p>{sub}</p></div>{action&&<button className="link-button" onClick={onAction}>{action} <ArrowRight size={14}/></button>}</div>}
function Empty({icon,title,text,action,onClick}){return <div className="empty"><Bubble>{icon}</Bubble><b>{title}</b><span>{text}</span>{action&&<Btn size="small" onClick={onClick}>{action}</Btn>}</div>}
function TokenList({tokens,windows,onCancel,onBook}){
  const rows=[...tokens].sort((a,b)=>new Date(b.booked_at)-new Date(a.booked_at))
  return <div className="panel full-panel"><PanelHead title="All your bookings" sub="Manage active tokens and review past visits."/>
    <div className="panel-action"><Btn size="small" onClick={onBook}><Plus size={15}/> New booking</Btn></div>
    {rows.length?<div className="table-wrap"><table><thead><tr><th>TOKEN</th><th>SERVICE WINDOW</th><th>APPOINTMENT</th><th>STATUS</th><th></th></tr></thead><tbody>{rows.map(t=><tr key={t.id}><td><b className="token-table">#{String(t.token_number).padStart(2,'0')}</b></td><td><b>{windows.find(w=>w.id===t.window_id)?.name||'Campus service'}</b><small>Queue position {t.queue_position}</small></td><td>{dateTime(t.slot?.starts_at||t.booked_at)}</td><td><Badge value={t.status}/></td><td>{ACTIVE.includes(t.status)&&<button className="cancel-link" onClick={()=>onCancel(t)}>Cancel</button>}</td></tr>)}</tbody></table></div>:<Empty icon={<Ticket/>} title="No bookings yet" text="Your tokens will show up here." action="Book your first token" onClick={onBook}/>}
  </div>
}
function StaffHome({queue,windows,windowId,setWindowId,onAction,onQueue,completed}){
  const arrived=queue.filter(t=>t.status==='arrived'),serving=queue.find(t=>t.status==='serving'),win=windows.find(w=>w.id===windowId)
  return <><div className="metric-grid"><Metric label="Waiting in queue" value={String(queue.filter(t=>t.status==='booked').length).padStart(2,'0')} hint="Active bookings" icon={<Users/>}/><Metric label="Arrived students" value={String(arrived.length).padStart(2,'0')} hint="Ready to be served" icon={<UserCheck/>}/><Metric label="Completed today" value={String(completed).padStart(2,'0')} hint="Across the campus" icon={<CheckCircle2/>}/></div>
    <div className="content-grid"><div className="panel"><PanelHead title="Counter overview" sub="Choose the service window you operate."/><select className="compact-select" value={windowId} onChange={e=>setWindowId(e.target.value)}>{windows.map(w=><option key={w.id} value={w.id}>{w.name}</option>)}</select>
      {win&&<div className="counter"><div className="counter-icon"><Building2 size={28}/><b>{win.name}</b><small>{win.location}</small></div><div><span className={'window-state '+win.status}>● {win.status}</span><h3>{serving?'Currently serving':'Ready for the next student'}</h3><p>{serving?serving.student_name+' · Token #'+serving.token_number:arrived.length+' student(s) have checked in.'}</p>{serving&&<Btn size="small" onClick={()=>onAction(serving,'complete')}><Check size={14}/> Mark complete</Btn>}</div></div>}
    </div><div className="panel"><PanelHead title="Arrivals to attend" sub="Physical arrival comes first." action="Full queue" onAction={onQueue}/>{arrived.length?arrived.slice(0,3).map(t=><div className="arrival" key={t.id}><div className="mini-avatar">{t.student_name?.slice(0,1)||'S'}</div><span><b>{t.student_name}</b><small>Token #{String(t.token_number).padStart(2,'0')}</small></span><Btn size="tiny" onClick={()=>onAction(t,'start')}>Call in</Btn></div>):<div className="empty-mini"><UserCheck size={22}/>No checked-in students right now.</div>}</div></div>
  </>
}
function QueuePage({queue,windows,windowId,setWindowId,onAction}){
  const win=windows.find(w=>w.id===windowId)
  return <div className="panel full-panel"><PanelHead title="Physical queue" sub="Mark arrivals, call a student, and close completed services."/>
    <select className="compact-select" value={windowId} onChange={e=>setWindowId(e.target.value)}>{windows.map(w=><option value={w.id} key={w.id}>{w.name}</option>)}</select>
    <div className="queue-banner"><div><small>NOW OPERATING</small><h3>{win?.name}</h3><p>{win?.location} · Earlier physical arrival receives priority within the same slot.</p></div><span className={'window-state '+win?.status}>● {win?.status}</span></div>
    {queue.length?<div>{queue.map(t=><div className="queue-row" key={t.id}><div className="queue-number">#{String(t.token_number).padStart(2,'0')}</div><div className="queue-person"><b>{t.student_name||'Student'}</b><small>{t.status==='arrived'?'Checked in · '+(t.arrived_at?time(t.arrived_at):'Just now'):t.status==='serving'?'At the counter now':'Awaiting arrival'}</small></div><Badge value={t.status}/><div className="queue-actions">{t.status==='booked'&&<Btn size="tiny" kind="soft" onClick={()=>onAction(t,'arrive')}>Mark arrived</Btn>}{t.status==='arrived'&&<Btn size="tiny" onClick={()=>onAction(t,'start')}>Call student</Btn>}{t.status==='serving'&&<Btn size="tiny" onClick={()=>onAction(t,'complete')}><Check size={13}/> Complete</Btn>}{['booked','arrived'].includes(t.status)&&<button className="cancel-link" onClick={()=>onAction(t,'cancel')}>No-show</button>}</div></div>)}</div>:<Empty icon={<Users/>} title="Queue is clear" text="New bookings will appear here automatically."/>}
  </div>
}
function WindowPage({windows,onToggle}){return <div className="window-grid">{windows.map(w=><div className="window-card" key={w.id}><div className="window-card-top"><Bubble><Building2/></Bubble><span className={'window-state '+w.status}>● {w.status}</span></div><h3>{w.name}</h3><p>{w.location}</p><div className="window-card-foot"><span>{w.status==='open'?'Accepting bookings':w.status==='break'?'Temporary break':'Not accepting bookings'}</span><Btn size="tiny" kind={w.status==='open'?'soft':'primary'} onClick={()=>onToggle(w)}>{w.status==='open'?'Close window':'Open window'}</Btn></div></div>)}</div>}
function AdminHome({data,pending,onServices,onReview}){
  const total=data.tokens.length,active=data.tokens.filter(t=>ACTIVE.includes(t.status)).length,done=data.tokens.filter(t=>t.status==='completed').length
  return <><div className="metric-grid four"><Metric label="Total tokens issued" value={String(total).padStart(2,'0')} hint="All recorded bookings" icon={<Ticket/>}/><Metric label="Active queue" value={String(active).padStart(2,'0')} hint="Bookings in progress" icon={<Users/>}/><Metric label="Services completed" value={String(done).padStart(2,'0')} hint="Successfully served" icon={<CheckCircle2/>}/><Metric label="Operational windows" value={String(data.windows.filter(w=>w.status==='open').length).padStart(2,'0')} hint="Currently open" icon={<DoorOpen/>}/></div>
    <div className="content-grid"><div className="panel"><PanelHead title="Service activity" sub="A snapshot of the campus service catalogue." action="Manage services" onAction={onServices}/>{data.works.map((w,i)=>{const wins=data.windows.filter(x=>x.work_id===w.id),n=data.tokens.filter(t=>wins.some(x=>x.id===t.window_id)).length;return <div className="activity-row" key={w.id}><Bubble tone={['','blue','purple','orange'][i]}><FileText/></Bubble><span><b>{w.name}</b><small>{wins.length} window(s) · {w.avg_service_minutes} min avg.</small></span><div className="mini-bar"><i style={{width:Math.min(100,Math.max(8,n*18))+'%'}}/></div><strong>{n}</strong></div>})}</div>
      <div className="panel"><PanelHead title="Break requests" sub="Review temporary counter closures."/><span className="count-badge">{pending.length} pending</span>{pending.length?pending.map(b=><BreakItem key={b.id} item={b} data={data} onReview={onReview}/>):<div className="empty-mini"><CheckCircle2 size={20}/>No pending break requests.</div>}</div></div>
  </>
}
function BreakItem({item,data,onReview}){return <div className="break-item"><div className="break-icon"><Coffee size={16}/></div><div><b>{data.windows.find(w=>w.id===item.window_id)?.name||'Service window'}</b><small>{item.reason}</small></div><div className="break-actions"><button onClick={()=>onReview(item,'approved')}>Approve</button><button onClick={()=>onReview(item,'rejected')}>Reject</button></div></div>}
function AdminServices({data,query,setQuery,onAddWork,onAddWindow,onToggle,pending,onReview}){
  const filtered=data.works.filter(w=>w.name.toLowerCase().includes(query.toLowerCase()))
  return <><div className="admin-toolbar"><div className="search"><Search size={16}/><input value={query} onChange={e=>setQuery(e.target.value)} placeholder="Search services…"/></div><div><Btn kind="soft" onClick={onAddWindow}><Plus size={15}/> Add window</Btn> <Btn onClick={onAddWork}><Plus size={15}/> Add service</Btn></div></div>
    <div className="admin-grid">{filtered.map(w=><div className="panel admin-service" key={w.id}><div className="service-card-head"><Bubble><FileText/></Bubble><span className="window-state open">● Active</span></div><h3>{w.name}</h3><p>{w.description||'Campus service'}</p><div className="service-stats"><div><b>{w.avg_service_minutes} min</b><small>Avg. service</small></div><div><b>{data.windows.filter(x=>x.work_id===w.id).length}</b><small>Windows</small></div><div><b>{data.tokens.filter(t=>data.windows.some(x=>x.work_id===w.id&&x.id===t.window_id)).length}</b><small>Tokens</small></div></div>
      {data.windows.filter(x=>x.work_id===w.id).map(x=><div className="service-window" key={x.id}><span>{x.name}</span><span className={'window-state '+x.status}>{x.status}</span><button onClick={()=>onToggle(x)}>{x.status==='open'?'Close':'Open'}</button></div>)}</div>)}</div>
    {pending.length>0&&<div className="panel break-panel"><PanelHead title="Pending break approvals" sub="Staff requests awaiting your review."/>{pending.map(b=><BreakItem key={b.id} item={b} data={data} onReview={onReview}/>)}</div>}
  </>
}
function Analytics({data}){
  const total=data.tokens.length,done=data.tokens.filter(t=>t.status==='completed').length,cancel=data.tokens.filter(t=>t.status==='cancelled').length
  const rows=data.works.map(w=>({name:w.name.split(' ')[0],n:data.tokens.filter(t=>data.windows.some(x=>x.work_id===w.id&&x.id===t.window_id)).length}))
  const max=Math.max(1,...rows.map(x=>x.n))
  return <><div className="metric-grid"><Metric label="Total bookings" value={String(total).padStart(2,'0')} hint="Recorded in prototype" icon={<Ticket/>}/><Metric label="Completion rate" value={(total?Math.round(done/total*100):0)+'%'} hint={done+' services completed'} icon={<Gauge/>}/><Metric label="Cancellation rate" value={(total?Math.round(cancel/total*100):0)+'%'} hint={cancel+' cancellations'} icon={<Activity/>}/></div>
    <div className="content-grid"><div className="panel"><PanelHead title="Bookings by service" sub="Distribution across the service catalogue."/><div className="chart-list">{rows.map(r=><div className="chart-row" key={r.name}><span>{r.name}</span><div className="chart-track"><i style={{width:r.n/max*100+'%'}}/></div><b>{r.n}</b></div>)}</div></div>
      <div className="panel"><PanelHead title="Queue outcomes" sub="How bookings are progressing."/><div className="outcomes"><div><i className="green-dot"/>Completed<b>{done}</b></div><div><i className="amber-dot"/>Active<b>{data.tokens.filter(t=>ACTIVE.includes(t.status)).length}</b></div><div><i className="red-dot"/>Cancelled<b>{cancel}</b></div></div><div className="analytics-note"><ShieldCheck size={15}/> Analytics reflect records currently stored in this prototype.</div></div></div>
  </>
}

import { useCallback, useEffect, useMemo, useState } from "react";
import {
  Activity, AlertCircle, ArrowRight, ArrowUpRight, BadgeCheck, Bell, Building2,
  CalendarDays, Check, CheckCircle2, ChevronDown, ChevronRight, Clock3, Coffee,
  DoorOpen, Download, Eye, EyeOff, FileCheck2, FileText, Filter, Gauge,
  LayoutDashboard, LockKeyhole, LogOut, Menu, MoreHorizontal, Plus, RefreshCw,
  Search, Settings, Shield, ShieldCheck, Ticket, UserCheck, UserPlus, Users,
  WalletCards, X, Zap, ClipboardList, CircleHelp, BarChart3, KeyRound, Save,
  Ban, RotateCcw, CalendarClock, GraduationCap,
} from "lucide-react";
import { supabase } from "./lib/supabase";

const ADMIN_SESSION_KEY = "offline_admin_session";
const ACTIVE = ["booked","arrived","serving"];
const dateKey = (d) => {
  const y=d.getFullYear(), m=String(d.getMonth()+1).padStart(2,"0"), day=String(d.getDate()).padStart(2,"0");
  return y+"-"+m+"-"+day;
};
const nextDates = (count=8) => {
  const out=[]; let d=new Date(); d.setHours(0,0,0,0);
  while(out.length<count){ if(d.getDay()!==0&&d.getDay()!==6)out.push(new Date(d)); d.setDate(d.getDate()+1); }
  return out;
};
const fmtTime = (value) => value ? new Date(value).toLocaleTimeString("en-IN",{hour:"numeric",minute:"2-digit"}) : "—";
const fmtDate = (value) => value ? new Date(value+"T12:00:00").toLocaleDateString("en-IN",{weekday:"short",day:"numeric",month:"short"}) : "—";
const fmtDateTime = (value) => value ? new Date(value).toLocaleString("en-IN",{weekday:"short",day:"numeric",month:"short",hour:"numeric",minute:"2-digit"}) : "—";
const fmtRelative = (value) => {
  if(!value)return "—";
  const mins=Math.max(0,Math.round((new Date(value).getTime()-Date.now())/60000));
  if(mins<60)return mins+" min";
  return Math.floor(mins/60)+"h "+(mins%60)+"m";
};
const initials = (name="Member") => name.split(/\s+/).slice(0,2).map(s=>s[0]||"").join("").toUpperCase();
const makePassword = (prefix="Off!") => {
  const bytes=window.crypto.getRandomValues(new Uint8Array(12));
  return prefix+Array.from(bytes,b=>b.toString(16).padStart(2,"0")).join("");
};
const statusLabel = (s) => ({booked:"Booked",arrived:"Arrived",serving:"In service",completed:"Completed",cancelled:"Cancelled"})[s]||s;
const Status = ({value}) => <span className={"status status-"+value}>{statusLabel(value)}</span>;
const Button = ({children,variant="primary",size="",...props}) => <button className={"btn btn-"+variant+" "+size} {...props}>{children}</button>;
const IconTile = ({children,tone=""}) => <span className={"icon-tile "+tone}>{children}</span>;
const Metric = ({label,value,hint,icon,tone=""}) => <article className="metric-card"><div className="metric-top"><span>{label}</span><IconTile tone={tone}>{icon}</IconTile></div><strong>{value}</strong><small>{hint}</small></article>;
const Field = ({label,children,hint}) => <label className="field"><span>{label}</span>{children}{hint&&<small>{hint}</small>}</label>;

async function adminCall(token,action,payload={}) {
  const {data,error}=await supabase.functions.invoke("offline-admin",{
    body:{action,...payload},
    headers:{"x-admin-session":token},
  });
  if(error) {
    const message=error.message||"Admin request failed.";
    throw new Error(message);
  }
  if(data?.error)throw new Error(data.error);
  return data;
}

function useRoute() {
  const [path,setPath]=useState(window.location.pathname);
  useEffect(()=>{
    const onPop=()=>setPath(window.location.pathname);
    window.addEventListener("popstate",onPop);
    return()=>window.removeEventListener("popstate",onPop);
  },[]);
  const go=useCallback((to)=>{
    if(window.location.pathname!==to)window.history.pushState({}, "", to);
    setPath(to);
    window.scrollTo({top:0,behavior:"instant"});
  },[]);
  return [path,go];
}

export default function App() {
  const [path,go]=useRoute();
  const [session,setSession]=useState(null);
  const [authReady,setAuthReady]=useState(false);

  useEffect(()=>{
    let mounted=true;
    supabase.auth.getSession().then(({data})=>{
      if(mounted){setSession(data.session);setAuthReady(true);}
    }).catch(()=>{if(mounted)setAuthReady(true);});
    const {data:listener}=supabase.auth.onAuthStateChange((_event,next)=>setSession(next));
    return()=>{mounted=false;listener.subscription.unsubscribe();};
  },[]);

  if(path==="/"||path==="")return <Landing go={go}/>;
  if(path==="/admin"||path==="/admin/")return <RouteRedirect to="/admin/login" go={go}/>;
  if(path==="/student"||path==="/student/")return <RouteRedirect to="/student/login" go={go}/>;
  if(path==="/staff"||path==="/staff/")return <RouteRedirect to="/staff/login" go={go}/>;

  if(path==="/admin/login")return <AdminLogin go={go}/>;
  if(path.startsWith("/admin/"))return <AdminWorkspace go={go}/>;

  if(path==="/student/login")return <RoleLogin role="student" go={go}/>;
  if(path==="/staff/login")return <RoleLogin role="staff" go={go}/>;

  if(path.startsWith("/student/")||path.startsWith("/staff/")) {
    if(!authReady)return <LoadingScreen text="Checking your campus account…"/>;
    if(!session){return <RouteRedirect to={path.startsWith("/staff/")?"/staff/login":"/student/login"} go={go}/>;}
    return path.startsWith("/staff/")?
      <StaffWorkspace session={session} path={path} go={go} onSignedOut={()=>setSession(null)}/>:
      <StudentWorkspace session={session} path={path} go={go} onSignedOut={()=>setSession(null)}/>;
  }
  return <NotFound go={go}/>;
}

function RouteRedirect({to,go}) {
  useEffect(()=>go(to),[to,go]);
  return <LoadingScreen text="Opening your workspace…"/>;
}

function LoadingScreen({text="Loading OffLine…"}) {
  return <div className="loading-screen"><div className="brand-mark">O<span>.</span></div><div className="loading-spinner"/><p>{text}</p></div>;
}

function Landing({go}) {
  return <div className="landing">
    <header className="landing-nav"><a className="brand" onClick={()=>go("/")}><span className="brand-mark">O<span>.</span></span><span><b>OffLine</b><small>Campus, without the queue.</small></span></a><div className="landing-nav-right"><span><i/> Campus services portal</span><Button variant="outline" onClick={()=>go("/admin/login")}><Shield size={15}/> Admin access</Button></div></header>
    <main className="landing-main">
      <section className="landing-hero">
        <div className="landing-copy"><p className="eyebrow">SMART CAMPUS OPERATIONS</p><h1>Your campus.<br/><em>Without the wait.</em></h1><p className="landing-intro">Book service appointments, manage counter queues and keep every campus visit moving with one connected workspace.</p><div className="landing-actions"><Button onClick={()=>go("/student/login")}>Student sign in <ArrowRight size={16}/></Button><Button onClick={()=>go("/staff/login")}>Staff sign in <ArrowRight size={16}/></Button></div><div className="landing-note"><ShieldCheck size={15}/> Accounts are issued by your campus administrator.</div></div>
        <div className="landing-visual"><div className="visual-ring ring-a"/><div className="visual-ring ring-b"/><div className="visual-ticket"><div><span>OFFLINE PASS</span><Ticket size={18}/></div><strong>08<span>.</span>24</strong><hr/><small>YOUR TURN, YOUR TIME</small><div className="visual-ticket-foot"><span>STUDENT SERVICES</span><b>CONFIRMED</b></div></div><div className="visual-floating"><CheckCircle2 size={16}/> Appointment confirmed</div><div className="visual-floating second"><Clock3 size={15}/> Queue updates live</div></div>
      </section>
      <section className="role-cards">
        <button className="role-card" onClick={()=>go("/student/login")}><IconTile><GraduationCap/></IconTile><span><b>Student portal</b><small>Book appointments, track your tokens and manage upcoming visits.</small></span><ArrowRight/></button>
        <button className="role-card" onClick={()=>go("/staff/login")}><IconTile tone="blue"><UserCheck/></IconTile><span><b>Staff workspace</b><small>Manage arrivals, call the next student and keep your counter running.</small></span><ArrowRight/></button>
        <button className="role-card" onClick={()=>go("/admin/login")}><IconTile tone="purple"><ShieldCheck/></IconTile><span><b>Administrator</b><small>Provision accounts, configure services and oversee campus operations.</small></span><ArrowRight/></button>
      </section>
    </main>
    <footer className="landing-footer"><span>© 2026 OffLine · Built for better campus days.</span><span>Secure, role-based campus access</span></footer>
  </div>;
}

function AdminLogin({go}) {
  const [passcode,setPasscode]=useState("");
  const [show,setShow]=useState(false);
  const [busy,setBusy]=useState(false);
  const [error,setError]=useState("");
  async function submit(e){
    e.preventDefault();setBusy(true);setError("");
    try {
      const {data,error}=await supabase.functions.invoke("offline-admin",{body:{action:"login",passcode}});
      if(error)throw new Error(error.message||"Admin login failed.");
      if(data?.error)throw new Error(data.error);
      if(!data?.session_token)throw new Error("The server did not issue an admin session.");
      sessionStorage.setItem(ADMIN_SESSION_KEY,data.session_token);
      go("/admin/dashboard");
    } catch(err){setError(err.message||"Unable to sign in.");}
    finally{setBusy(false);}
  }
  return <AuthShell go={go} role="admin" title="Administrator access" subtitle="Enter the passcode issued physically by your campus." onSubmit={submit} busy={busy} error={error}>
    <Field label="Administrator passcode"><div className="password-wrap"><input autoFocus required autoComplete="off" type={show?"text":"password"} value={passcode} onChange={e=>setPasscode(e.target.value)} placeholder="Enter your admin passcode"/><button type="button" onClick={()=>setShow(!show)}>{show?<EyeOff size={16}/>:<Eye size={16}/>}</button></div></Field>
    <Button block disabled={busy||!passcode.trim()}>{busy?"Verifying passcode…":"Enter admin dashboard"} <ArrowRight size={16}/></Button>
  </AuthShell>;
}

function RoleLogin({role,go}) {
  const [email,setEmail]=useState("");
  const [password,setPassword]=useState("");
  const [show,setShow]=useState(false);
  const [busy,setBusy]=useState(false);
  const [error,setError]=useState("");
  const title=role==="student"?"Student sign in":"Staff sign in";
  async function submit(e){
    e.preventDefault();setBusy(true);setError("");
    try {
      const {data,error}=await supabase.auth.signInWithPassword({email:email.trim().toLowerCase(),password});
      if(error)throw error;
      const {data:profile,error:profileError}=await supabase.from("offline_profiles").select("id,full_name,role,account_status,college_id").eq("id",data.user.id).single();
      if(profileError){await supabase.auth.signOut();throw new Error("This account has not been provisioned by your administrator.");}
      if(profile.account_status!=="active"){await supabase.auth.signOut();throw new Error("Your account is inactive. Contact the campus administrator.");}
      if(profile.role!==role){await supabase.auth.signOut();throw new Error("These credentials belong to a different portal.");}
      go(role==="_staff"?"/staff/dashboard":role==="staff"?"/staff/dashboard":"/student/dashboard");
    } catch(err){setError(err.message||"Sign in failed.");}
    finally{setBusy(false);}
  }
  return <AuthShell go={go} role={role} title={title} subtitle={role==="student"?"Sign in with the credentials provided by your campus.":"Use your staff account issued by the administrator."} onSubmit={submit} busy={busy} error={error}>
    <Field label="Email address"><input required type="email" autoComplete="username" value={email} onChange={e=>setEmail(e.target.value)} placeholder="name@college.edu"/></Field>
    <Field label="Password"><div className="password-wrap"><input required autoComplete="current-password" type={show?"text":"password"} value={password} onChange={e=>setPassword(e.target.value)} placeholder="Enter your password"/><button type="button" onClick={()=>setShow(!show)}>{show?<EyeOff size={16}/>:<Eye size={16}/>}</button></div></Field>
    <Button block disabled={busy||!email||!password}>{busy?"Signing in…":"Sign in"} <ArrowRight size={16}/></Button>
    <p className="auth-issuance">No public registration. Ask your administrator to create or reset your account.</p>
  </AuthShell>;
}

function AuthShell({go,role,title,subtitle,onSubmit,busy,error,children}) {
  const roleLabel=role==="admin"?"ADMINISTRATION":role==="staff"?"STAFF PORTAL":"STUDENT PORTAL";
  return <div className="auth-page"><header className="auth-top"><a className="brand" onClick={()=>go("/")}><span className="brand-mark">O<span>.</span></span><span><b>OffLine</b><small>Campus, without the queue.</small></span></a><button className="back-link" onClick={()=>go("/")}> <ChevronRight className="back-chevron"/> Back to home</button></header>
    <main className="auth-layout"><section className="auth-aside"><p className="eyebrow">{roleLabel}</p><h1>{role==="admin"?"One campus. Full control.":role==="staff"?"Keep the queue moving.":"Your time is yours again."}</h1><p>{role==="admin"?"Manage people, services, counters and day-to-day campus operations from a single secure workspace.":role==="staff"?"Handle student arrivals, move the service queue and keep students informed about your counter.":"Reserve the service you need, know when to arrive and skip the physical waiting line."}</p><div className="auth-points"><span><CheckCircle2/> Role-based access</span><span><CheckCircle2/> Live queue updates</span><span><CheckCircle2/> Campus service records</span></div></section>
      <section className="auth-card"><div className="auth-card-icon">{role==="admin"?<ShieldCheck/>:role==="staff"?<UserCheck/>:<GraduationCap/>}</div><p className="eyebrow">{roleLabel}</p><h2>{title}</h2><p className="muted">{subtitle}</p><form className="form-stack" onSubmit={onSubmit}>{children}{error&&<div className="form-error"><AlertCircle size={15}/>{error}</div>}</form><div className="auth-card-foot"><LockKeyhole size={14}/> Secure sign-in · OffLine Campus</div></section>
    </main><footer className="auth-footer">© 2026 OffLine <span>Campus operations platform</span></footer>
  </div>;
}

function PortalFrame({role,profile,nav,active,go,onSignOut,children,actions}) {
  const title=role==="admin"?"Campus administration":role==="staff"?"Staff workspace":"Student portal";
  return <div className="portal-shell">
    <aside className="portal-sidebar">
      <a className="brand" onClick={()=>go(role==="admin"?"/admin/dashboard":role==="staff"?"/staff/dashboard":"/student/dashboard")}><span className="brand-mark">O<span>.</span></span><span><b>OffLine</b><small>Campus, without the queue.</small></span></a>
      <div className="side-workspace"><span className="side-role-icon">{role==="admin"?<ShieldCheck/>:role==="staff"?<UserCheck/>:<GraduationCap/>}</span><span><small>WORKSPACE</small><b>{title}</b></span></div>
      <p className="side-caption">MENU</p>
      <nav className="side-nav">{nav.map(item=><button key={item.id} className={"side-nav-item "+(active===item.id?"active":"")} onClick={()=>go(item.path)}><item.icon size={18}/><span>{item.label}</span>{active===item.id&&<i/>}</button>)}</nav>
      <div className="side-bottom"><div className="side-help"><CircleHelp size={17}/><b>Need support?</b><small>Contact your campus administrator for help with your account or services.</small></div><div className="side-user"><div className="avatar">{initials(profile?.full_name||"User")}</div><span><b>{profile?.full_name||"Campus member"}</b><small>{profile?.college_id||role.toUpperCase()}</small></span><button title="Sign out" onClick={onSignOut}><LogOut size={17}/></button></div></div>
    </aside>
    <main className="portal-main"><header className="portal-topbar"><div className="portal-breadcrumb"><span>OffLine</span><ChevronRight size={14}/><b>{nav.find(n=>n.id===active)?.label||"Overview"}</b></div><div className="portal-top-actions"><span className="top-date"><CalendarDays size={15}/>{new Date().toLocaleDateString("en-IN",{weekday:"short",day:"numeric",month:"short"})}</span><span className={"role-chip "+role}>{role==="admin"?"Administrator":role==="staff"?"Staff":"Student"}</span><div className="avatar small">{initials(profile?.full_name||"User")}</div></div></header><div className="portal-content">{children}</div><footer className="portal-footer"><span>© 2026 OffLine · Built for better campus days.</span><span><i/> Connected to campus services</span></footer></main>
  </div>;
}

function PageHeading({eyebrow,title,sub,action}) {
  return <div className="page-heading"><div><p className="eyebrow">{eyebrow}</p><h1>{title}</h1><p>{sub}</p></div>{action&&<div className="heading-action">{action}</div>}</div>;
}
function Panel({title,sub,action,children,className=""}) {
  return <section className={"panel "+className}><div className="panel-heading"><div><h3>{title}</h3>{sub&&<p>{sub}</p>}</div>{action}</div>{children}</section>;
}
function EmptyState({icon,title,text,action}) {
  return <div className="empty-state"><IconTile>{icon}</IconTile><b>{title}</b><span>{text}</span>{action}</div>;
}

function StudentWorkspace({session,path,go,onSignedOut}) {
  const [profile,setProfile]=useState(null);
  const [services,setServices]=useState([]);
  const [windows,setWindows]=useState([]);
  const [slots,setSlots]=useState([]);
  const [tokens,setTokens]=useState([]);
  const [slotUsage,setSlotUsage]=useState({});
  const [loading,setLoading]=useState(true);
  const [error,setError]=useState("");
  const [toast,setToast]=useState("");
  const [selectedWork,setSelectedWork]=useState("");
  const [selectedWindow,setSelectedWindow]=useState("");
  const [selectedDate,setSelectedDate]=useState(dateKey(new Date()));
  const [selectedSlot,setSelectedSlot]=useState("");

  const page=path.endsWith("/book")?"book":path.endsWith("/tokens")?"tokens":"overview";
  const nav=[
    {id:"overview",label:"Overview",icon:LayoutDashboard,path:"/student/dashboard"},
    {id:"book",label:"Book a service",icon:CalendarDays,path:"/student/book"},
    {id:"tokens",label:"My tokens",icon:Ticket,path:"/student/tokens"},
  ];
  const notify=(msg)=>{setToast(msg);window.clearTimeout(notify.timer);notify.timer=window.setTimeout(()=>setToast(""),3200);};
  const load=useCallback(async()=>{
    setLoading(true);setError("");
    try {
      const {data:p,error:pe}=await supabase.from("offline_profiles").select("*").eq("id",session.user.id).single();
      if(pe)throw pe;
      if(p.role!=="student"||p.account_status!=="active"){await supabase.auth.signOut();onSignedOut();go("/student/login");return;}
      const [w,ws,s,t]=await Promise.all([
        supabase.from("offline_works").select("*").eq("active",true).order("name"),
        supabase.from("offline_windows").select("*").order("name"),
        supabase.from("offline_slots").select("*").gte("slot_date",dateKey(new Date())).order("starts_at").limit(800),
        supabase.from("offline_tokens").select("*,slot:offline_slots(*),window:offline_windows(*)").eq("student_id",session.user.id).order("booked_at",{ascending:false}),
      ]);
      const failed=[w,ws,s,t].find(x=>x.error);if(failed?.error)throw failed.error;
      const usage=await supabase.rpc("offline_slot_usage",{p_slot_ids:(s.data||[]).map(x=>x.id)});
      if(usage.error)throw usage.error;
      setSlotUsage(Object.fromEntries((usage.data||[]).map(x=>[x.slot_id,Number(x.used_count)])));
      setProfile(p);setServices(w.data||[]);setWindows(ws.data||[]);setSlots(s.data||[]);setTokens(t.data||[]);
      if(!selectedWork&&w.data?.[0])setSelectedWork(w.data[0].id);
      if(!selectedWindow){
        const defaultWorkId=selectedWork||w.data?.[0]?.id;
        const matchingWindow=(ws.data||[]).find(x=>x.work_id===defaultWorkId);
        if(matchingWindow)setSelectedWindow(matchingWindow.id);
      }
    } catch(e){setError(e.message||"Could not load student workspace.");}
    finally{setLoading(false);}
  },[session.user.id,go,onSignedOut,selectedWork,selectedWindow]);
  useEffect(()=>{load();},[session.user.id]);
  useEffect(()=>{
    const channel=supabase.channel("offline-student-"+session.user.id)
      .on("postgres_changes",{event:"*",schema:"public",table:"offline_tokens",filter:"student_id=eq."+session.user.id},()=>{load();})
      .subscribe();
    return()=>{supabase.removeChannel(channel);};
  },[session.user.id,load]);

  const serviceWindows=windows.filter(w=>w.work_id===selectedWork);
  const currentWindow=windows.find(w=>w.id===selectedWindow);
  const options=slots.filter(s=>s.window_id===selectedWindow&&s.slot_date===selectedDate)
    .map(s=>({...s,used:slotUsage?.[s.id]||0}))
    .filter(s=>new Date(s.starts_at)>new Date()&&s.used<s.capacity)
    .sort((a,b)=>new Date(a.starts_at)-new Date(b.starts_at));
  const active=tokens.filter(t=>ACTIVE.includes(t.status));
  const upcoming=[...active].sort((a,b)=>new Date(a.slot?.starts_at||a.booked_at)-new Date(b.slot?.starts_at||b.booked_at))[0];
  const serviceName=(token)=>services.find(w=>windows.find(win=>win.id===token.window_id)?.work_id===w.id)?.name||"Campus service";

  async function book(){
    if(!selectedSlot)return notify("Choose an available appointment first.");
    if(currentWindow?.status!=="open")return notify("This service window is not accepting bookings.");
    const {error:e}=await supabase.rpc("offline_book_token",{p_slot_id:selectedSlot});
    if(e)return notify(e.message);
    setSelectedSlot("");await load();go("/student/tokens");notify("Your token has been booked.");
  }
  async function cancel(token){
    const {error:e}=await supabase.rpc("offline_cancel_own_token",{p_token_id:token.id});
    if(e)return notify(e.message);
    await load();notify("Token cancelled successfully.");
  }
  async function signOut(){await supabase.auth.signOut();onSignedOut();go("/");}

  if(loading&&!profile)return <LoadingScreen text="Opening your student portal…"/>;
  return <PortalFrame role="student" profile={profile} nav={nav} active={page} go={go} onSignOut={signOut}>
    {error&&<div className="inline-error"><AlertCircle size={16}/>{error}</div>}
    {page==="overview"&&<StudentOverview profile={profile} services={services} windows={windows} tokens={tokens} upcoming={upcoming} go={go}/>}
    {page==="book"&&<StudentBooking services={services} windows={windows} slots={slots} slotUsage={slotUsage} selectedWork={selectedWork} setSelectedWork={setSelectedWork} selectedWindow={selectedWindow} setSelectedWindow={setSelectedWindow} selectedDate={selectedDate} setSelectedDate={setSelectedDate} selectedSlot={selectedSlot} setSelectedSlot={setSelectedSlot} onBook={book}/>}
    {page==="tokens"&&<StudentTokenPage tokens={tokens} windows={windows} services={services} onCancel={cancel} go={go}/>}
    {toast&&<Toast>{toast}</Toast>}
  </PortalFrame>;
}

function StudentOverview({profile,services,windows,tokens,upcoming,go}) {
  const active=tokens.filter(t=>ACTIVE.includes(t.status)).length;
  const completed=tokens.filter(t=>t.status==="completed").length;
  return <>
    <PageHeading eyebrow="YOUR CAMPUS, ON YOUR TIME" title={"Good day, "+(profile?.full_name||"there").split(" ")[0]+"."} sub="A little less waiting. A lot more living." action={<Button onClick={()=>go("/student/book")}><Plus size={16}/> Book a service</Button>}/>
    <section className="student-hero"><div><span className="hero-label"><Zap size={13}/> TIME IS YOURS AGAIN</span><h2>Do the work.<br/><em>Skip the wait.</em></h2><p>Reserve your spot at a campus counter, track your turn and spend less time standing in line.</p><Button onClick={()=>go("/student/book")}>Find a service <ArrowRight size={16}/></Button></div><div className="hero-art"><div className="hero-rings"/><div className="hero-pass"><small>OFFLINE PASS <Ticket size={17}/></small><strong>08<span>.</span>24</strong><hr/><b>YOUR TURN, YOUR TIME</b></div><span className="hero-float"><CheckCircle2 size={15}/> Appointment confirmed</span></div></section>
    <div className="metric-grid three"><Metric label="Active tokens" value={String(active).padStart(2,"0")} hint="Your upcoming bookings" icon={<Ticket/>}/><Metric label="Available services" value={String(services.length).padStart(2,"0")} hint="Across campus" icon={<Building2/>} tone="blue"/><Metric label="Visits completed" value={String(completed).padStart(2,"0")} hint="Successfully served" icon={<CheckCircle2/>} tone="purple"/></div>
    <div className="content-grid">
      <Panel title="Your next appointment" sub="Your upcoming service at a glance." action={<button className="link-button" onClick={()=>go("/student/tokens")}>All tokens <ArrowRight size={14}/></button>}>
        {upcoming?<div className="next-token-card"><div className="next-token-number"><small>YOUR TOKEN</small><strong>#{String(upcoming.token_number).padStart(2,"0")}</strong><Status value={upcoming.status}/></div><div className="next-token-detail"><span><small>Service window</small><b>{windows.find(w=>w.id===upcoming.window_id)?.name||"Campus counter"}</b></span><span><small>Appointment</small><b>{fmtDateTime(upcoming.slot?.starts_at||upcoming.booked_at)}</b></span><span><small>Queue position</small><b>{upcoming.queue_position||"—"}</b></span></div></div>:<EmptyState icon={<Ticket/>} title="No upcoming tokens" text="Book a service and your appointment will appear here." action={<Button size="small" onClick={()=>go("/student/book")}>Book a token</Button>}/>}
      </Panel>
      <Panel title="Popular campus services" sub="Get started with a campus essential.">
        <div className="shortcut-list">{services.slice(0,5).map((s,i)=><div className="shortcut-row" key={s.id}><IconTile tone={i%2?"blue":""}>{i===0?<FileText/>:i===1?<FileCheck2/>:i===2?<WalletCards/>:<ClipboardList/>}</IconTile><span><b>{s.name}</b><small>{s.avg_service_minutes} min · Average service time</small></span><ChevronRight size={17}/></div>)}</div>
      </Panel>
    </div>
  </>;
}

function StudentBooking({services,windows,slots,slotUsage,selectedWork,setSelectedWork,selectedWindow,setSelectedWindow,selectedDate,setSelectedDate,selectedSlot,setSelectedSlot,onBook}) {
  const dates=nextDates(8);
  const work=services.find(s=>s.id===selectedWork);
  const serviceWindows=windows.filter(w=>w.work_id===selectedWork);
  const window=windows.find(w=>w.id===selectedWindow);
  const options=slots.filter(s=>s.window_id===selectedWindow&&s.slot_date===selectedDate)
    .map(s=>({...s,used:Number(slotUsage?.[s.id]||0)}))
    .filter(s=>new Date(s.starts_at)>new Date()&&s.used<s.capacity).sort((a,b)=>new Date(a.starts_at)-new Date(b.starts_at));
  return <>
    <PageHeading eyebrow="APPOINTMENT BOOKING" title="Book a service." sub="Choose what you need. We'll take care of your place in line."/>
    <div className="booking-layout"><div className="booking-main">
      <section className="step-card"><StepTitle n="01" title="What do you need done?" sub="Select the campus service you want to visit."/><div className="service-picker">{services.map((s,i)=><button key={s.id} className={"service-select "+(selectedWork===s.id?"chosen":"")} onClick={()=>{setSelectedWork(s.id);setSelectedWindow(windows.find(w=>w.work_id===s.id)?.id||"");setSelectedSlot("");}}><IconTile tone={["","blue","purple","orange"][i%4]}>{i===0?<FileText/>:i===1?<FileCheck2/>:i===2?<WalletCards/>:<ClipboardList/>}</IconTile><span><b>{s.name}</b><small>{s.description||"Campus service"} · {s.avg_service_minutes} min</small></span>{selectedWork===s.id?<CheckCircle2 className="selected-mark"/>:<ChevronRight className="subtle-icon"/>}</button>)}</div></section>
      <section className="step-card"><StepTitle n="02" title="Pick a service window" sub="Choose where you want to be served."/><div className="window-picker">{serviceWindows.map(w=><button key={w.id} className={"window-select "+(selectedWindow===w.id?"chosen":"")} onClick={()=>{setSelectedWindow(w.id);setSelectedSlot("");}}><span><b>{w.name}</b><small><Building2 size={13}/>{w.location}</small></span><span className={"window-state "+w.status}>● {w.status}</span></button>)}</div></section>
      <section className="step-card"><StepTitle n="03" title="When works for you?" sub="Appointments are one hour. The last 15 minutes are reserved as buffer."/><div className="date-strip">{dates.map(d=><button key={dateKey(d)} className={"date-option "+(selectedDate===dateKey(d)?"chosen":"")} onClick={()=>{setSelectedDate(dateKey(d));setSelectedSlot("");}}><small>{d.toLocaleDateString("en-IN",{weekday:"short"})}</small><b>{d.getDate()}</b><small>{d.toLocaleDateString("en-IN",{month:"short"})}</small></button>)}</div><div className="slot-grid">{options.length?options.map(s=><button key={s.id} className={"slot-option "+(selectedSlot===s.id?"chosen":"")} onClick={()=>setSelectedSlot(s.id)}><b>{fmtTime(s.starts_at)}</b><small>{s.capacity-s.used} spots left</small></button>):<div className="empty-slots"><Clock3/><b>No available slots</b><span>Try another date or service window.</span></div>}</div><div className="lunch-reminder"><Coffee size={14}/> Lunch closure: 12:00 PM – 1:00 PM · No appointments during this time.</div></section>
    </div>
    <aside className="booking-summary"><p className="eyebrow">YOUR APPOINTMENT</p><h3>Almost there.</h3><p className="muted">Review your selection before confirming.</p><SummaryRow label="Service" value={work?.name||"Choose a service"}/><SummaryRow label="Service window" value={window?.name||"Choose a window"}/><SummaryRow label="Date" value={fmtDate(selectedDate)}/><SummaryRow label="Time" value={selectedSlot?fmtTime(slots.find(s=>s.id===selectedSlot)?.starts_at):"Choose a slot"}/><div className="eta-info"><Clock3 size={17}/><span><b>Smart queue estimate</b><small>Your estimated turn updates as the counter works through the queue.</small></span></div><Button block disabled={!selectedSlot||window?.status!=="open"} onClick={onBook}>Confirm appointment <ArrowRight size={16}/></Button><small className="summary-privacy"><ShieldCheck size={13}/> No payment required. Cancel before service.</small></aside></div>
  </>;
}
function StepTitle({n,title,sub}){return <div className="step-title"><span>{n}</span><div><h3>{title}</h3><p>{sub}</p></div></div>;}
function SummaryRow({label,value}){return <div className="summary-row"><small>{label}</small><b>{value}</b></div>;}
function StudentTokenPage({tokens,windows,services,onCancel,go}) {
  const sorted=[...tokens].sort((a,b)=>new Date(b.booked_at)-new Date(a.booked_at));
  return <><PageHeading eyebrow="YOUR BOOKINGS" title="My tokens." sub="Every appointment, every update, all in one place." action={<Button onClick={()=>go("/student/book")}><Plus size={16}/> New booking</Button>}/>
    <div className="token-summary-strip"><div><Ticket/><span><small>Total bookings</small><b>{tokens.length}</b></span></div><div><Clock3/><span><small>Active</small><b>{tokens.filter(t=>ACTIVE.includes(t.status)).length}</b></span></div><div><CheckCircle2/><span><small>Completed</small><b>{tokens.filter(t=>t.status==="completed").length}</b></span></div></div>
    <Panel title="Appointment history" sub="Track current bookings and review earlier visits." className="full-panel">
      {sorted.length?<div className="table-scroll"><table className="data-table"><thead><tr><th>TOKEN</th><th>SERVICE / WINDOW</th><th>APPOINTMENT</th><th>QUEUE POSITION</th><th>STATUS</th><th></th></tr></thead><tbody>{sorted.map(t=><tr key={t.id}><td><b className="token-id">#{String(t.token_number).padStart(2,"0")}</b></td><td><b>{windows.find(w=>w.id===t.window_id)?.name||"Campus counter"}</b><small>{t.slot?.slot_date?fmtDate(t.slot.slot_date):"Appointment"}</small></td><td>{fmtDateTime(t.slot?.starts_at||t.booked_at)}</td><td>#{t.queue_position||"—"}</td><td><Status value={t.status}/></td><td>{ACTIVE.includes(t.status)&&<button className="text-danger" onClick={()=>onCancel(t)}>Cancel</button>}</td></tr>)}</tbody></table></div>:<EmptyState icon={<Ticket/>} title="No tokens yet" text="Your confirmed appointments will appear here." action={<Button size="small" onClick={()=>go("/student/book")}>Book your first service</Button>}/>}
    </Panel>
  </>;
}

function StaffWorkspace({session,path,go,onSignedOut}) {
  const [profile,setProfile]=useState(null);
  const [windows,setWindows]=useState([]);
  const [tokens,setTokens]=useState([]);
  const [loading,setLoading]=useState(true);
  const [error,setError]=useState("");
  const [toast,setToast]=useState("");
  const [windowId,setWindowId]=useState("");
  const [breakModal,setBreakModal]=useState(false);
  const [breakReason,setBreakReason]=useState("");
  const [busy,setBusy]=useState(false);
  const page=path.endsWith("/queue")?"queue":path.endsWith("/windows")?"windows":"overview";
  const nav=[
    {id:"overview",label:"Overview",icon:LayoutDashboard,path:"/staff/dashboard"},
    {id:"queue",label:"Live queue",icon:Users,path:"/staff/queue"},
    {id:"windows",label:"Window operations",icon:DoorOpen,path:"/staff/windows"},
  ];
  const notify=(s)=>{setToast(s);window.clearTimeout(notify.timer);notify.timer=window.setTimeout(()=>setToast(""),3200);};
  const load=useCallback(async()=>{
    setLoading(true);setError("");
    try{
      const {data:p,error:pe}=await supabase.from("offline_profiles").select("*").eq("id",session.user.id).single();
      if(pe)throw pe;
      if(p.role!=="staff"||p.account_status!=="active"){await supabase.auth.signOut();onSignedOut();go("/staff/login");return;}
      const [w,t]=await Promise.all([
        supabase.from("offline_windows").select("*").eq("staff_id",session.user.id).order("name"),
        supabase.from("offline_tokens").select("*,slot:offline_slots(*),window:offline_windows(*),student:offline_profiles(full_name,college_id)").order("booked_at",{ascending:false}).limit(500),
      ]);
      const failed=[w,t].find(x=>x.error);if(failed?.error)throw failed.error;
      setProfile(p);setWindows(w.data||[]);
      const assignedIds=(w.data||[]).map(x=>x.id);
      setTokens((t.data||[]).filter(x=>assignedIds.includes(x.window_id)).map(x=>({...x,student_name:x.student?.full_name||"Student",student_college_id:x.student?.college_id||""})));
      if(!windowId&&w.data?.[0])setWindowId(w.data[0].id);
    }catch(e){setError(e.message||"Could not load staff workspace.");}
    finally{setLoading(false);}
  },[session.user.id,go,onSignedOut,windowId]);
  useEffect(()=>{load();},[session.user.id]);
  useEffect(()=>{
    const channel=supabase.channel("offline-staff-"+session.user.id)
      .on("postgres_changes",{event:"*",schema:"public",table:"offline_tokens"},()=>{load();})
      .on("postgres_changes",{event:"*",schema:"public",table:"offline_windows",filter:"staff_id=eq."+session.user.id},()=>{load();})
      .subscribe();
    return()=>{supabase.removeChannel(channel);};
  },[session.user.id,load]);
  const win=windows.find(w=>w.id===windowId);
  const queue=tokens.filter(t=>t.window_id===windowId&&ACTIVE.includes(t.status)).sort((a,b)=>{
    const rank={serving:0,arrived:1,booked:2};
    return rank[a.status]-rank[b.status]||new Date(a.arrived_at||a.booked_at)-new Date(b.arrived_at||b.booked_at);
  });
  const arrived=queue.filter(t=>t.status==="arrived");
  const serving=queue.find(t=>t.status==="serving");
  async function action(token,act){
    setBusy(true);
    try{
      const {error}=await supabase.rpc("offline_staff_update_token",{p_token_id:token.id,p_action:act,p_reason:act==="cancel"?"Late / no-show":null});
      if(error)throw error;
      await load();notify(({arrive:"Arrival recorded.",start:"Student called to the counter.",complete:"Service completed.",cancel:"Token marked as no-show."})[act]);
    }catch(e){notify(e.message||"Action failed.");}
    finally{setBusy(false);}
  }
  async function toggleWindow(w){
    const next=w.status==="open"?"closed":"open";
    const {error}=await supabase.from("offline_windows").update({status:next}).eq("id",w.id);
    if(error)return notify(error.message);
    await load();notify("Counter "+next+".");
  }
  async function requestBreak(e){
    e.preventDefault();
    if(!breakReason.trim())return notify("Please enter the reason for the break.");
    const {error}=await supabase.from("offline_break_requests").insert({window_id:windowId,requested_by:profile.id,reason:breakReason.trim()});
    if(error)return notify(error.message);
    setBreakModal(false);setBreakReason("");notify("Emergency break request sent to the administrator.");
  }
  async function signOut(){await supabase.auth.signOut();onSignedOut();go("/");}
  if(loading&&!profile)return <LoadingScreen text="Opening your staff workspace…"/>;
  return <PortalFrame role="staff" profile={profile} nav={nav} active={page} go={go} onSignOut={signOut}>
    {error&&<div className="inline-error"><AlertCircle size={16}/>{error}</div>}
    {page==="overview"&&<StaffOverview windows={windows} win={win} windowId={windowId} setWindowId={setWindowId} queue={queue} arrived={arrived} serving={serving} tokens={tokens} onAction={action} go={go} onBreak={()=>setBreakModal(true)}/>}
    {page==="queue"&&<StaffQueuePage windows={windows} win={win} windowId={windowId} setWindowId={setWindowId} queue={queue} onAction={action} busy={busy}/>}
    {page==="windows"&&<StaffWindowPage windows={windows} onToggle={toggleWindow} onBreak={(id)=>{setWindowId(id);setBreakModal(true);}}/>}
    {toast&&<Toast>{toast}</Toast>}
    {breakModal&&<Modal title="Request an emergency break" eyebrow="COUNTER OPERATIONS" onClose={()=>setBreakModal(false)}><form className="form-stack" onSubmit={requestBreak}><p className="muted">This request will be sent to the campus administrator. Your counter remains open until the request is reviewed.</p><Field label="Reason for the break"><textarea required rows="4" value={breakReason} onChange={e=>setBreakReason(e.target.value)} placeholder="Briefly describe why the counter needs to pause."/></Field><div className="modal-actions"><Button type="button" variant="ghost" onClick={()=>setBreakModal(false)}>Cancel</Button><Button type="submit">Send request <ArrowRight size={15}/></Button></div></form></Modal>}
  </PortalFrame>;
}

function StaffOverview({windows,win,windowId,setWindowId,queue,arrived,serving,tokens,onAction,go,onBreak}) {
  return <>
    <PageHeading eyebrow="SERVICE OPERATIONS" title={"Welcome, "+(windows[0]?.name?"team member":"staff member")+"."} sub="Keep the line moving. Students are updated as you work." action={<Button variant="outline" onClick={onBreak}><Coffee size={15}/> Request break</Button>}/>
    <div className="metric-grid three"><Metric label="Waiting for arrival" value={String(queue.filter(t=>t.status==="booked").length).padStart(2,"0")} hint="Booked, not checked in" icon={<Clock3/>}/><Metric label="Students checked in" value={String(arrived.length).padStart(2,"0")} hint="Ready to be served" icon={<UserCheck/>} tone="blue"/><Metric label="Completed visits" value={String(tokens.filter(t=>t.status==="completed").length).padStart(2,"0")} hint="All assigned counters" icon={<CheckCircle2/>} tone="purple"/></div>
    <div className="content-grid">
      <Panel title="Counter at a glance" sub="Select an assigned window to see its current state." action={<select className="compact-select" value={windowId} onChange={e=>setWindowId(e.target.value)}>{windows.map(w=><option key={w.id} value={w.id}>{w.name}</option>)}</select>}>
        {win?<div className="counter-spotlight"><div className="counter-illustration"><Building2 size={29}/><b>{win.name}</b><small>{win.location}</small></div><div className="counter-copy"><span className={"window-state "+win.status}>● {win.status}</span><h3>{serving?"Currently serving":"Ready for the next student"}</h3><p>{serving?"Token #"+serving.token_number+" is at the counter.":arrived.length+" student(s) checked in and waiting."}</p>{serving&&<Button size="small" disabled={false} onClick={()=>onAction(serving,"complete")}><Check size={14}/> Mark complete</Button>}</div></div>:<EmptyState icon={<DoorOpen/>} title="No counter assigned" text="Ask your administrator to assign a service window to your staff account."/>}
      </Panel>
      <Panel title="Next arrivals" sub="Students are served after physical arrival.">
        {arrived.length?arrived.slice(0,4).map(t=><div className="arrival-row" key={t.id}><div className="avatar mini">{initials(t.student_name||"Student")}</div><span><b>{t.student_name||"Student"}</b><small>Token #{String(t.token_number).padStart(2,"0")} · Checked in</small></span><Button size="tiny" onClick={()=>onAction(t,"start")}>Call in</Button></div>):<EmptyState icon={<UserCheck/>} title="No checked-in students" text="New arrivals will appear here once the staff marks them as present."/>}
      </Panel>
    </div>
  </>;
}

function StaffQueuePage({windows,win,windowId,setWindowId,queue,onAction,busy}) {
  return <><PageHeading eyebrow="COUNTER OPERATIONS" title="Live queue." sub="Mark arrivals, call a student and complete each service."/><Panel title="Physical queue" sub="The queue is filtered to the windows assigned to your account." action={<select className="compact-select" value={windowId} onChange={e=>setWindowId(e.target.value)}>{windows.map(w=><option key={w.id} value={w.id}>{w.name}</option>)}</select>}>
    {win&&<div className="queue-context"><div><small>NOW OPERATING</small><b>{win.name}</b><span>{win.location} · Earlier arrival is prioritised within the appointment slot.</span></div><span className={"window-state "+win.status}>● {win.status}</span></div>}
    {queue.length?<div className="queue-list">{queue.map(t=><div className={"queue-row "+(t.status==="serving"?"is-serving":"")} key={t.id}><div className="queue-number">#{String(t.token_number).padStart(2,"0")}</div><div className="queue-student"><b>{t.student_name||"Student"}</b><small>{t.status==="arrived"?"Checked in · "+fmtTime(t.arrived_at):t.status==="serving"?"At counter now":"Awaiting physical arrival"}</small></div><Status value={t.status}/><div className="queue-actions">{t.status==="booked"&&<Button size="tiny" variant="soft" disabled={busy} onClick={()=>onAction(t,"arrive")}>Mark arrived</Button>}{t.status==="arrived"&&<Button size="tiny" disabled={busy} onClick={()=>onAction(t,"start")}>Call student</Button>}{t.status==="serving"&&<Button size="tiny" disabled={busy} onClick={()=>onAction(t,"complete")}><Check size={13}/> Complete</Button>}{["booked","arrived"].includes(t.status)&&<button className="text-danger" onClick={()=>onAction(t,"cancel")}>No-show</button>}</div></div>)}</div>:<EmptyState icon={<Users/>} title="Queue is clear" text="New appointments for this counter will appear here."/>}
  </Panel></>;
}
function StaffWindowPage({windows,onToggle,onBreak}) {
  return <><PageHeading eyebrow="COUNTER STATUS" title="Window operations." sub="Open or close your assigned service counters and request a temporary break."/><div className="window-grid">{windows.map(w=><article className="window-card" key={w.id}><div className="window-card-top"><IconTile><Building2/></IconTile><span className={"window-state "+w.status}>● {w.status}</span></div><h3>{w.name}</h3><p>{w.location}</p><div className="window-card-actions"><Button size="small" variant={w.status==="open"?"soft":"primary"} onClick={()=>onToggle(w)}>{w.status==="open"?"Close window":"Open window"}</Button><Button size="small" variant="outline" onClick={()=>onBreak(w.id)}><Coffee size={14}/> Request break</Button></div></article>)}</div></>;
}

function AdminWorkspace({go}) {
  const [token,setToken]=useState(()=>sessionStorage.getItem(ADMIN_SESSION_KEY)||"");
  const [page,setPage]=useState("overview");
  const [data,setData]=useState({users:[],services:[],windows:[],slots:[],tokens:[],breaks:[]});
  const [loading,setLoading]=useState(true);
  const [error,setError]=useState("");
  const [toast,setToast]=useState("");
  const [modal,setModal]=useState("");
  const [createdCredentials,setCreatedCredentials]=useState([]);
  const [seedMessage,setSeedMessage]=useState("");
  const [editRecord,setEditRecord]=useState(null);
  const [search,setSearch]=useState("");
  const [saving,setSaving]=useState(false);

  const notify=(s)=>{setToast(s);window.clearTimeout(notify.timer);notify.timer=window.setTimeout(()=>setToast(""),3400);};
  async function refresh(){
    const result=await adminCall(token,"dashboard");
    setData(result);
    return result;
  }
  useEffect(()=>{
    let cancelled=false;
    if(!token){go("/admin/login");return;}
    setLoading(true);setError("");
    adminCall(token,"dashboard").then(async result=>{
      if(cancelled)return;
      if((result.users||[]).length===0){
        const seeded=await adminCall(token,"seed_demo");
        if(!cancelled){setCreatedCredentials(seeded.users||[]);setSeedMessage(seeded.message||"Sample accounts created.");setPage("people");}
        result=await adminCall(token,"dashboard");
      }
      if(!cancelled)setData(result);
    })
      .catch(e=>{if(!cancelled){setError(e.message||"Admin session expired.");if((e.message||"").toLowerCase().includes("session")){sessionStorage.removeItem(ADMIN_SESSION_KEY);setToken("");go("/admin/login");}}})
      .finally(()=>{if(!cancelled)setLoading(false);});
    return()=>{cancelled=true;};
  },[token]);

  async function signOut(){
    try{await adminCall(token,"logout");}catch{}
    sessionStorage.removeItem(ADMIN_SESSION_KEY);setToken("");go("/");
  }
  async function seedDemo(){
    setSaving(true);setError("");
    try{
      const result=await adminCall(token,"seed_demo");
      setCreatedCredentials(result.users||[]);setSeedMessage(result.message||"Sample accounts have been created.");
      await refresh();setPage("people");
    }catch(e){setError(e.message||"Could not seed demo accounts.");}
    finally{setSaving(false);}
  }
  async function saveUser(form){
    setSaving(true);
    try{
      const result=await adminCall(token,"create_user",form);
      setCreatedCredentials([result.user]);setModal("");await refresh();notify("Account created successfully.");
    }catch(e){setError(e.message||"Account could not be created.");}
    finally{setSaving(false);}
  }
  async function updateUser(payload){
    setSaving(true);
    try{await adminCall(token,"update_user",payload);await refresh();notify("Account updated.");}
    catch(e){setError(e.message||"Account update failed.");}
    finally{setSaving(false);}
  }
  async function resetPassword(id,password){
    setSaving(true);
    try{await adminCall(token,"reset_password",{id,password});notify("Password reset. Share the new password securely.");setCreatedCredentials([{email:data.users.find(u=>u.id===id)?.email,full_name:data.users.find(u=>u.id===id)?.full_name,role:data.users.find(u=>u.id===id)?.role,initial_password:password}]);}
    catch(e){setError(e.message||"Password reset failed.");}
    finally{setSaving(false);}
  }
  async function saveService(payload){
    setSaving(true);
    try{await adminCall(token,"save_service",payload);setModal("");await refresh();notify("Service saved.");}
    catch(e){setError(e.message||"Could not save service.");}
    finally{setSaving(false);}
  }
  async function saveWindow(payload){
    setSaving(true);
    try{const result=await adminCall(token,"save_window",payload);setModal("");await refresh();notify(result.slots_created?("Window created with "+result.slots_created+" slots."): "Window updated.");}
    catch(e){setError(e.message||"Could not save window.");}
    finally{setSaving(false);}
  }
  async function setWindowStatus(id,status){
    setSaving(true);
    try{await adminCall(token,"set_window_status",{id,status});await refresh();notify("Window status updated.");}
    catch(e){setError(e.message||"Could not update window.");}
    finally{setSaving(false);}
  }
  async function decideBreak(id,status){
    setSaving(true);
    try{await adminCall(token,"decide_break",{id,status});await refresh();notify("Break request "+status+".");}
    catch(e){setError(e.message||"Could not review break.");}
    finally{setSaving(false);}
  }
  if(loading)return <LoadingScreen text="Opening administrator control centre…"/>;

  const nav=[
    {id:"overview",label:"Overview",icon:LayoutDashboard},
    {id:"people",label:"People & accounts",icon:Users},
    {id:"services",label:"Services",icon:ClipboardList},
    {id:"windows",label:"Service windows",icon:Building2},
    {id:"bookings",label:"Bookings & breaks",icon:Ticket},
    {id:"analytics",label:"Reports & analytics",icon:BarChart3},
  ];
  const filteredUsers=data.users.filter(u=>(u.full_name+" "+u.email+" "+u.college_id).toLowerCase().includes(search.toLowerCase()));
  const openCount=data.windows.filter(w=>w.status==="open").length;
  const activeTokens=data.tokens.filter(t=>ACTIVE.includes(t.status)).length;
  const today=dateKey(new Date());
  const todayTokens=data.tokens.filter(t=>(t.booked_at||"").slice(0,10)===today).length;
  return <div className="portal-shell">
    <aside className="portal-sidebar admin-sidebar">
      <a className="brand" onClick={()=>go("/admin/dashboard")}><span className="brand-mark">O<span>.</span></span><span><b>OffLine</b><small>Campus, without the queue.</small></span></a>
      <div className="admin-profile-card"><span className="admin-shield"><ShieldCheck/></span><span><small>SECURE CONSOLE</small><b>Administrator</b><em>Passcode authenticated</em></span></div>
      <p className="side-caption">CONTROL CENTRE</p>
      <nav className="side-nav">{nav.map(n=><button key={n.id} className={"side-nav-item "+(page===n.id?"active":"")} onClick={()=>setPage(n.id)}><n.icon size={18}/><span>{n.label}</span>{page===n.id&&<i/>}</button>)}</nav>
      <div className="side-bottom"><div className="side-help"><ShieldCheck size={17}/><b>Administrator authority</b><small>Create users, manage operations and oversee all campus queues.</small></div><div className="side-user"><div className="avatar">AD</div><span><b>Campus Admin</b><small>Administrator</small></span><button title="Sign out" onClick={signOut}><LogOut size={17}/></button></div></div>
    </aside>
    <main className="portal-main"><header className="portal-topbar"><div className="portal-breadcrumb"><span>OffLine</span><ChevronRight size={14}/><b>{nav.find(n=>n.id===page)?.label||"Overview"}</b></div><div className="portal-top-actions"><span className="secure-label"><LockKeyhole size={14}/> Admin session active</span><button className="icon-button" onClick={()=>refresh()} title="Refresh data"><RefreshCw size={17}/></button><span className="role-chip admin">Administrator</span></div></header>
      <div className="portal-content">
        {error&&<div className="inline-error"><AlertCircle size={16}/>{error}<button onClick={()=>setError("")}><X size={14}/></button></div>}
        {page==="overview"&&<AdminOverview data={data} todayTokens={todayTokens} activeTokens={activeTokens} openCount={openCount} setPage={setPage} seedDemo={seedDemo} saving={saving}/>}
        {page==="people"&&<AdminPeople users={filteredUsers} search={search} setSearch={setSearch} onCreate={()=>setModal("user")} onUpdate={updateUser} onReset={resetPassword} onSeed={seedDemo} saving={saving}/>}
        {page==="services"&&<AdminServices data={data} onAdd={()=>setModal("service")} onEdit={s=>{setModal("service");setEditRecord(s);}} onSave={saveService} saving={saving}/>}
        {page==="windows"&&<AdminWindows data={data} onAdd={()=>setModal("window")} onEdit={w=>{setModal("window");setEditRecord(w);}} onSave={saveWindow} onStatus={setWindowStatus} saving={saving}/>}
        {page==="bookings"&&<AdminBookings data={data} onReview={decideBreak} saving={saving}/>}
        {page==="analytics"&&<AdminAnalytics data={data}/>}
      </div>
      <footer className="portal-footer"><span>© 2026 OffLine · Administrator control centre.</span><span><i/> Database connected</span></footer>
    </main>
    {toast&&<Toast>{toast}</Toast>}
    {createdCredentials.length>0&&<CredentialsModal users={createdCredentials} onClose={()=>setCreatedCredentials([])} title="Account credentials"/>}
    {modal==="user"&&<UserModal onClose={()=>setModal("")} onSave={saveUser} saving={saving}/>}
    {modal==="service"&&<ServiceModal initial={editRecord} onClose={()=>{setModal("");setEditRecord(null);}} onSave={saveService} saving={saving}/>}
    {modal==="window"&&<WindowModal initial={editRecord} data={data} onClose={()=>{setModal("");setEditRecord(null);}} onSave={saveWindow} saving={saving}/>}
  </div>;
}

function AdminOverview({data,todayTokens,activeTokens,openCount,setPage,seedDemo,saving}) {
  const students=data.users.filter(u=>u.role==="student").length,staff=data.users.filter(u=>u.role==="staff").length;
  const done=data.tokens.filter(t=>t.status==="completed").length;
  const pending=data.breaks.filter(b=>b.status==="pending");
  const recent=[...data.tokens].sort((a,b)=>new Date(b.booked_at)-new Date(a.booked_at)).slice(0,6);
  return <>
    <PageHeading eyebrow="CAMPUS CONTROL CENTRE" title="Good day, Administrator." sub="A complete operational view of your campus service network." action={<Button variant="outline" onClick={()=>setPage("people")}><UserPlus size={16}/> Create account</Button>}/>
    {data.users.length===0&&<div className="seed-banner"><div><span><Zap/></span><div><b>Set up your sample campus accounts</b><p>Create demo students and staff, assign staff to windows and add sample queue records.</p></div></div><Button disabled={saving} onClick={seedDemo}>{saving?"Creating sample accounts…":"Seed demo accounts"} <ArrowRight size={15}/></Button></div>}
    <div className="metric-grid four"><Metric label="Students" value={String(students).padStart(2,"0")} hint="Provisioned accounts" icon={<GraduationCap/>}/><Metric label="Staff members" value={String(staff).padStart(2,"0")} hint="Counter operators" icon={<UserCheck/>} tone="blue"/><Metric label="Active tokens" value={String(activeTokens).padStart(2,"0")} hint="Bookings in progress" icon={<Ticket/>} tone="purple"/><Metric label="Open windows" value={String(openCount).padStart(2,"0")} hint="Accepting appointments" icon={<DoorOpen/>} tone="orange"/></div>
    <div className="content-grid admin-overview-grid"><Panel title="Operational snapshot" sub="Today's service activity across the campus." action={<button className="link-button" onClick={()=>setPage("analytics")}>View reports <ArrowRight size={14}/></button>}><div className="admin-stat-list"><div><span>Appointments booked today</span><b>{todayTokens}</b></div><div><span>Services completed</span><b>{done}</b></div><div><span>Pending break requests</span><b>{pending.length}</b></div><div><span>Registered services</span><b>{data.services.length}</b></div></div><div className="snapshot-actions"><button onClick={()=>setPage("people")}><Users size={16}/> Manage accounts</button><button onClick={()=>setPage("windows")}><Building2 size={16}/> Configure windows</button></div></Panel>
      <Panel title="Recent bookings" sub="Latest token activity." action={<button className="link-button" onClick={()=>setPage("bookings")}>All bookings <ArrowRight size={14}/></button>}>{recent.length?<div className="recent-list">{recent.map(t=><div className="recent-row" key={t.id}><div className="avatar mini">{initials(data.users.find(u=>u.id===t.student_id)?.full_name||"S")}</div><span><b>{data.users.find(u=>u.id===t.student_id)?.full_name||"Student"}</b><small>Token #{String(t.token_number).padStart(2,"0")} · {data.windows.find(w=>w.id===t.window_id)?.name||"Counter"}</small></span><Status value={t.status}/></div>)}</div>:<EmptyState icon={<Ticket/>} title="No bookings yet" text="Student appointments will appear here."/>}</Panel>
    </div>
    <div className="admin-quicklinks"><button onClick={()=>setPage("people")}><IconTile><UserPlus/></IconTile><span><b>Provision accounts</b><small>Create a student or staff login.</small></span><ArrowRight/></button><button onClick={()=>setPage("services")}><IconTile tone="blue"><ClipboardList/></IconTile><span><b>Manage services</b><small>Set service times and availability.</small></span><ArrowRight/></button><button onClick={()=>setPage("windows")}><IconTile tone="purple"><DoorOpen/></IconTile><span><b>Manage counters</b><small>Assign staff and appointment windows.</small></span><ArrowRight/></button></div>
  </>;
}

function AdminPeople({users,search,setSearch,onCreate,onUpdate,onReset,onSeed,saving}) {
  const [resetUser,setResetUser]=useState(null);
  const [newPassword,setNewPassword]=useState("");
  return <>
    <PageHeading eyebrow="PEOPLE & ACCESS" title="People and accounts." sub="Create and manage the student and staff accounts that can access OffLine." action={<Button onClick={onCreate}><UserPlus size={16}/> Create account</Button>}/>
    {users.length===0&&<div className="seed-banner compact"><div><span><Zap/></span><div><b>No accounts have been provisioned yet.</b><p>Seed sample users for the prototype, or create your first account.</p></div></div><Button disabled={saving} onClick={onSeed}>Seed demo accounts</Button></div>}
    <div className="people-summary"><div><b>{users.filter(u=>u.role==="student").length}</b><small>Students</small></div><div><b>{users.filter(u=>u.role==="staff").length}</b><small>Staff</small></div><div><b>{users.filter(u=>u.account_status==="inactive").length}</b><small>Inactive</small></div></div>
    <Panel title="Directory" sub="All accounts issued by the administrator."><div className="table-toolbar"><div className="search-control"><Search size={16}/><input value={search} onChange={e=>setSearch(e.target.value)} placeholder="Search by name, email or ID"/></div><span className="results-count">{users.length} account(s)</span></div>
      {users.length?<div className="table-scroll"><table className="data-table"><thead><tr><th>PERSON</th><th>COLLEGE / STAFF ID</th><th>ROLE</th><th>STATUS</th><th>CREATED</th><th>ACTIONS</th></tr></thead><tbody>{users.map(u=><tr key={u.id}><td><div className="person-cell"><div className="avatar mini">{initials(u.full_name)}</div><span><b>{u.full_name}</b><small>{u.email}</small></span></div></td><td>{u.college_id||"—"}</td><td><span className={"role-tag "+u.role}>{u.role}</span></td><td><span className={"account-state "+u.account_status}>{u.account_status}</span></td><td>{fmtDate((u.created_at||"").slice(0,10))}</td><td><div className="table-actions"><button title="Reset password" onClick={()=>{setResetUser(u);setNewPassword(makePassword(u.role==="staff"?"Stf!":"Stu!"));}}><KeyRound size={15}/></button><button title={u.account_status==="active"?"Deactivate account":"Activate account"} onClick={()=>onUpdate({id:u.id,account_status:u.account_status==="active"?"inactive":"active"})}>{u.account_status==="active"?<Ban size={15}/>:<CheckCircle2 size={15}/>}</button></div></td></tr>)}</tbody></table></div>:<EmptyState icon={<Users/>} title="No matching accounts" text="Create an account to give a student or staff member access." action={<Button size="small" onClick={onCreate}>Create account</Button>}/>}
    </Panel>
    {resetUser&&<Modal title="Reset account password" eyebrow="ACCOUNT SECURITY" onClose={()=>setResetUser(null)}><form className="form-stack" onSubmit={e=>{e.preventDefault();onReset(resetUser.id,newPassword);setResetUser(null);}}><p className="muted">Set a new temporary password for <b>{resetUser.full_name}</b>. Share it with the account holder through a secure channel.</p><Field label="New password"><input required minLength="10" value={newPassword} onChange={e=>setNewPassword(e.target.value)}/></Field><div className="modal-actions"><Button type="button" variant="ghost" onClick={()=>setResetUser(null)}>Cancel</Button><Button type="submit"><Save size={15}/> Reset password</Button></div></form></Modal>}
  </>;
}

function AdminServices({data,onAdd,onEdit,onSave,saving}) {
  const [search,setSearch]=useState("");
  const filtered=data.services.filter(s=>s.name.toLowerCase().includes(search.toLowerCase()));
  return <><PageHeading eyebrow="SERVICE CATALOGUE" title="Campus services." sub="Configure what students can book and how long each visit typically takes." action={<Button onClick={onAdd}><Plus size={16}/> Add service</Button>}/>
    <div className="table-toolbar"><div className="search-control"><Search size={16}/><input value={search} onChange={e=>setSearch(e.target.value)} placeholder="Search service catalogue"/></div><span className="results-count">{data.services.length} service(s)</span></div>
    <div className="admin-service-grid">{filtered.map(s=><article className="admin-service-card" key={s.id}><div className="service-top"><IconTile><FileText/></IconTile><span className={"account-state "+(s.active?"active":"inactive")}>{s.active?"Active":"Hidden"}</span></div><h3>{s.name}</h3><p>{s.description||"Campus service"}</p><div className="service-kpis"><div><b>{s.avg_service_minutes} min</b><small>Average service</small></div><div><b>{data.windows.filter(w=>w.work_id===s.id).length}</b><small>Windows</small></div><div><b>{data.tokens.filter(t=>data.windows.some(w=>w.id===t.window_id&&w.work_id===s.id)).length}</b><small>Tokens</small></div></div><Button block variant="outline" size="small" onClick={()=>onEdit(s)}>Edit service <ArrowRight size={14}/></Button></article>)}</div>
  </>;
}

function AdminWindows({data,onAdd,onEdit,onStatus,saving}) {
  return <><PageHeading eyebrow="COUNTER CONFIGURATION" title="Service windows." sub="Create service counters, assign staff and control appointment availability." action={<Button onClick={onAdd}><Plus size={16}/> Add service window</Button>}/>
    <div className="window-grid admin-window-grid">{data.windows.map(w=><article className="window-card" key={w.id}><div className="window-card-top"><IconTile><Building2/></IconTile><span className={"window-state "+w.status}>● {w.status}</span></div><h3>{w.name}</h3><p>{w.location}</p><div className="assigned-staff"><small>ASSIGNED STAFF</small><b>{data.users.find(u=>u.id===w.staff_id)?.full_name||"Not assigned"}</b></div><div className="window-card-metrics"><span>{data.services.find(s=>s.id===w.work_id)?.name||"Service"}</span><b>{data.slots.filter(s=>s.window_id===w.id).length} slots</b></div><div className="window-card-actions"><Button size="small" variant="outline" onClick={()=>onEdit(w)}>Edit assignment</Button><Button size="small" variant={w.status==="open"?"soft":"primary"} onClick={()=>onStatus(w.id,w.status==="open"?"closed":"open")}>{w.status==="open"?"Close window":"Open window"}</Button></div></article>)}</div>
  </>;
}

function AdminBookings({data,onReview,saving}) {
  const [filter,setFilter]=useState("all");
  const list=data.tokens.filter(t=>filter==="all"||t.status===filter).sort((a,b)=>new Date(b.booked_at)-new Date(a.booked_at));
  const pending=data.breaks.filter(b=>b.status==="pending");
  return <><PageHeading eyebrow="QUEUE OVERSIGHT" title="Bookings and break requests." sub="Review the campus-wide queue and manage exceptional counter interruptions."/>
    <div className="filter-tabs">{["all","booked","arrived","serving","completed","cancelled"].map(s=><button key={s} className={filter===s?"active":""} onClick={()=>setFilter(s)}>{s==="all"?"All bookings":statusLabel(s)}</button>)}</div>
    <Panel title="All booking records" sub="Bookings across every campus service window." className="full-panel">{list.length?<div className="table-scroll"><table className="data-table"><thead><tr><th>TOKEN</th><th>STUDENT</th><th>WINDOW</th><th>APPOINTMENT</th><th>STATUS</th></tr></thead><tbody>{list.map(t=><tr key={t.id}><td><b className="token-id">#{String(t.token_number).padStart(2,"0")}</b></td><td><b>{data.users.find(u=>u.id===t.student_id)?.full_name||"Student"}</b><small>{data.users.find(u=>u.id===t.student_id)?.college_id||"—"}</small></td><td>{data.windows.find(w=>w.id===t.window_id)?.name||"Window"}</td><td>{fmtDateTime(data.slots.find(s=>s.id===t.slot_id)?.starts_at||t.booked_at)}</td><td><Status value={t.status}/></td></tr>)}</tbody></table></div>:<EmptyState icon={<Ticket/>} title="No bookings in this view" text="Change the status filter or wait for students to book appointments."/>}</Panel>
    <Panel title="Emergency break approvals" sub="Staff can request a break; administrators decide whether a counter should pause." className="break-approvals">{pending.length?pending.map(b=><div className="break-approval-row" key={b.id}><IconTile tone="orange"><Coffee/></IconTile><span><b>{data.windows.find(w=>w.id===b.window_id)?.name||"Service window"}</b><small>{b.reason}</small></span><Button size="small" disabled={saving} onClick={()=>onReview(b.id,"approved")}>Approve</Button><Button size="small" variant="outline" disabled={saving} onClick={()=>onReview(b.id,"rejected")}>Reject</Button></div>):<EmptyState icon={<CheckCircle2/>} title="No pending break requests" text="Staff requests will appear here for your review."/>}</Panel>
  </>;
}

function AdminAnalytics({data}) {
  const total=data.tokens.length,done=data.tokens.filter(t=>t.status==="completed").length,cancel=data.tokens.filter(t=>t.status==="cancelled").length,active=data.tokens.filter(t=>ACTIVE.includes(t.status)).length;
  const bars=data.services.map(s=>({name:s.name,n:data.tokens.filter(t=>data.windows.some(w=>w.work_id===s.id&&w.id===t.window_id)).length}));
  const max=Math.max(1,...bars.map(b=>b.n));
  return <><PageHeading eyebrow="PERFORMANCE & INSIGHTS" title="Reports and analytics." sub="A real-time view of service demand and queue outcomes."/>
    <div className="metric-grid four"><Metric label="Total bookings" value={String(total).padStart(2,"0")} hint="All recorded appointments" icon={<Ticket/>}/><Metric label="Completion rate" value={(total?Math.round(done/total*100):0)+"%"} hint={done+" completed visits"} icon={<Gauge/>} tone="blue"/><Metric label="Cancellation rate" value={(total?Math.round(cancel/total*100):0)+"%"} hint={cancel+" cancellations"} icon={<Activity/>} tone="purple"/><Metric label="Active queue" value={String(active).padStart(2,"0")} hint="Currently active tokens" icon={<Users/>} tone="orange"/></div>
    <div className="content-grid"><Panel title="Bookings by service" sub="Distribution across the campus catalogue."><div className="chart-list">{bars.map(b=><div className="chart-row" key={b.name}><span>{b.name}</span><div className="chart-track"><i style={{width:(b.n/max*100)+"%"}}/></div><b>{b.n}</b></div>)}</div></Panel><Panel title="Queue outcomes" sub="Current token status distribution."><div className="outcome-list"><div><i className="green"/><span>Completed</span><b>{done}</b></div><div><i className="amber"/><span>Active</span><b>{active}</b></div><div><i className="red"/><span>Cancelled</span><b>{cancel}</b></div></div><div className="analytics-footnote"><ShieldCheck size={15}/> Calculated from live OffLine booking records.</div></Panel></div>
  </>;
}

function UserModal({onClose,onSave,saving}) {
  const [role,setRole]=useState("student"),[full_name,setName]=useState(""),[email,setEmail]=useState(""),[college_id,setId]=useState(""),[password,setPassword]=useState(makePassword("Stu!"));
  return <Modal title="Create a campus account" eyebrow="NEW ACCOUNT" onClose={onClose}><form className="form-stack" onSubmit={e=>{e.preventDefault();onSave({role,full_name,email,college_id,password});}}>
    <div className="role-choice"><button type="button" className={role==="student"?"active":""} onClick={()=>{setRole("student");setPassword(makePassword("Stu!"));}}><GraduationCap size={16}/> Student</button><button type="button" className={role==="staff"?"active":""} onClick={()=>{setRole("staff");setPassword(makePassword("Stf!"));}}><UserCheck size={16}/> Staff</button></div>
    <Field label="Full name"><input required value={full_name} onChange={e=>setName(e.target.value)} placeholder="Enter full name"/></Field>
    <Field label="Email address"><input type="email" required value={email} onChange={e=>setEmail(e.target.value)} placeholder="name@college.edu"/></Field>
    <Field label={role==="student"?"College roll number":"Staff ID"}><input required value={college_id} onChange={e=>setId(e.target.value)} placeholder={role==="student"?"e.g. 245703441":"e.g. STF-001"}/></Field>
    <Field label="Initial password" hint="At least 10 characters. Share this with the account holder privately."><div className="generate-input"><input required minLength="10" value={password} onChange={e=>setPassword(e.target.value)}/><button type="button" onClick={()=>setPassword(makePassword(role==="staff"?"Stf!":"Stu!"))}><RefreshCw size={14}/> Generate</button></div></Field>
    <div className="modal-actions"><Button type="button" variant="ghost" onClick={onClose}>Cancel</Button><Button type="submit" disabled={saving}>{saving?"Creating…":"Create account"} <ArrowRight size={15}/></Button></div>
  </form></Modal>;
}

function ServiceModal({initial,onClose,onSave,saving}) {
  const [name,setName]=useState(initial?.name||""),[description,setDescription]=useState(initial?.description||""),[avg_service_minutes,setDuration]=useState(initial?.avg_service_minutes||10),[active,setActive]=useState(initial?.active!==false);
  return <Modal title={initial?"Edit service":"Add a service"} eyebrow="SERVICE CATALOGUE" onClose={onClose}><form className="form-stack" onSubmit={e=>{e.preventDefault();onSave({id:initial?.id,name,description,avg_service_minutes,active});}}>
    <Field label="Service name"><input required value={name} onChange={e=>setName(e.target.value)} placeholder="e.g. Library Clearance"/></Field><Field label="Description"><textarea rows="3" value={description} onChange={e=>setDescription(e.target.value)} placeholder="Describe what students need for this service."/></Field><Field label="Average service duration (minutes)"><input type="number" min="1" max="45" required value={avg_service_minutes} onChange={e=>setDuration(e.target.value)}/></Field><label className="toggle-field"><span><b>Available to students</b><small>Students can see and book this service.</small></span><input type="checkbox" checked={active} onChange={e=>setActive(e.target.checked)}/></label>
    <div className="modal-actions"><Button type="button" variant="ghost" onClick={onClose}>Cancel</Button><Button type="submit" disabled={saving}><Save size={15}/> Save service</Button></div>
  </form></Modal>;
}

function WindowModal({initial,data,onClose,onSave,saving}) {
  const [name,setName]=useState(initial?.name||""),[work_id,setWork]=useState(initial?.work_id||data.services[0]?.id||""),[location,setLocation]=useState(initial?.location||"Administrative Block"),[staff_id,setStaff]=useState(initial?.staff_id||"");
  return <Modal title={initial?"Edit service window":"Create service window"} eyebrow="COUNTER CONFIGURATION" onClose={onClose}><form className="form-stack" onSubmit={e=>{e.preventDefault();onSave({id:initial?.id,name,work_id,location,staff_id});}}>
    <Field label="Window name"><input required value={name} onChange={e=>setName(e.target.value)} placeholder="e.g. Window 05 · Library"/></Field>
    <Field label="Service"><select required value={work_id} onChange={e=>setWork(e.target.value)}>{data.services.map(s=><option key={s.id} value={s.id}>{s.name}</option>)}</select></Field>
    <Field label="Location"><input required value={location} onChange={e=>setLocation(e.target.value)} placeholder="Administrative Block"/></Field>
    <Field label="Assigned staff member"><select value={staff_id} onChange={e=>setStaff(e.target.value)}><option value="">Unassigned</option>{data.users.filter(u=>u.role==="staff"&&u.account_status==="active").map(u=><option key={u.id} value={u.id}>{u.full_name} · {u.college_id}</option>)}</select></Field>
    {!initial&&<p className="modal-note"><CalendarClock size={15}/> Ten weekdays of one-hour appointment slots will be generated automatically, excluding the lunch hour.</p>}
    <div className="modal-actions"><Button type="button" variant="ghost" onClick={onClose}>Cancel</Button><Button type="submit" disabled={saving}><Save size={15}/> Save window</Button></div>
  </form></Modal>;
}

function CredentialsModal({users,onClose,title}) {
  return <Modal title={title} eyebrow="SHARE SECURELY" onClose={onClose} wide><p className="credentials-warning"><ShieldCheck size={17}/> These initial passwords are shown only now. Copy them and share each with the correct account holder privately.</p><div className="credentials-list">{users.map(u=><article className="credential-card" key={u.id||u.email}><div><span className={"role-tag "+u.role}>{u.role}</span><b>{u.full_name}</b><small>{u.college_id} · {u.email}</small></div><div className="credential-line"><span><small>INITIAL PASSWORD</small><code>{u.password||u.initial_password}</code></span><button onClick={()=>navigator.clipboard.writeText(u.password||u.initial_password)}><ClipboardList size={15}/> Copy</button></div></article>)}</div><div className="modal-actions"><Button onClick={onClose}>Done</Button></div></Modal>;
}

function Modal({title,eyebrow,children,onClose,wide=false}) {
  return <div className="modal-backdrop" onMouseDown={e=>{if(e.target===e.currentTarget)onClose();}}><section className={"modal-card "+(wide?"wide":"")}><header className="modal-head"><div><p className="eyebrow">{eyebrow}</p><h2>{title}</h2></div><button className="icon-button" onClick={onClose}><X size={18}/></button></header>{children}</section></div>;
}
function Toast({children}){return <div className="toast"><CheckCircle2 size={17}/>{children}</div>;}
function NotFound({go}){return <div className="not-found"><div className="brand-mark">O<span>.</span></div><h1>Page not found</h1><p>This OffLine route does not exist.</p><Button onClick={()=>go("/")}>Return home</Button></div>;}

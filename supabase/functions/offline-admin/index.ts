import { createClient } from "npm:@supabase/supabase-js@2";
const cors={"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization, apikey, content-type, x-client-info, x-admin-session","Access-Control-Allow-Methods":"POST, OPTIONS"};
const out=(v:unknown,s=200)=>new Response(JSON.stringify(v),{status:s,headers:{...cors,"Content-Type":"application/json"}});
const env=(k:string)=>Deno.env.get(k)||"";
function key(){if(env("SUPABASE_SERVICE_ROLE_KEY"))return env("SUPABASE_SERVICE_ROLE_KEY");const m=JSON.parse(env("SUPABASE_SECRET_KEYS")||"{}");if(m.default)return m.default;throw new Error("Server secret key unavailable");}
const db=createClient(env("SUPABASE_URL")||"https://kjhraamalsrfpecsinrz.supabase.co",key(),{auth:{persistSession:false,autoRefreshToken:false}});
async function hash(v:string){const b=await crypto.subtle.digest("SHA-256",new TextEncoder().encode(v));return Array.from(new Uint8Array(b),x=>x.toString(16).padStart(2,"0")).join("");}
function rand(){return Array.from(crypto.getRandomValues(new Uint8Array(32)),x=>x.toString(16).padStart(2,"0")).join("");}
function txt(v:unknown,n=180){return typeof v==="string"?v.trim().slice(0,n):"";}
function dateIST(d:Date){return new Intl.DateTimeFormat("en-CA",{timeZone:"Asia/Kolkata",year:"numeric",month:"2-digit",day:"2-digit"}).format(d);}
function dayIST(d:Date){return new Intl.DateTimeFormat("en-US",{timeZone:"Asia/Kolkata",weekday:"short"}).format(d);}
function makeSlots(wid:string,duration:number){const rows:Record<string,unknown>[]=[];let step=1,days=0;while(days<10&&step<24){const d=new Date(Date.now()+step*86400000),day=dateIST(d),wd=dayIST(d);if(wd!=="Sat"&&wd!=="Sun"){for(const h of [9,10,11,13,14,15,16]){const a=String(h).padStart(2,"0"),b=String(h+1).padStart(2,"0");rows.push({window_id:wid,slot_date:day,starts_at:new Date(day+"T"+a+":00:00+05:30").toISOString(),ends_at:new Date(day+"T"+b+":00:00+05:30").toISOString(),capacity:Math.max(1,Math.floor(45/Math.max(1,duration))),buffer_minutes:15});}days++;}step++;}return rows;}
async function isAdmin(req:Request){const raw=req.headers.get("x-admin-session")||"";if(raw.length<48)return null;const {data,error}=await db.from("offline_admin_sessions").select("id").eq("token_hash",await hash(raw)).is("revoked_at",null).gt("expires_at",new Date().toISOString()).maybeSingle();return error||!data?null:data;}
async function createUser(b:Record<string,unknown>){
  const role=b.role==="staff"?"staff":b.role==="student"?"student":"";
  const email=txt(b.email,200).toLowerCase();
  const name=txt(b.full_name,120);
  const college=txt(b.college_id,80);
  const password=typeof b.password==="string"?b.password:"";
  if(!role||!email.includes("@")||!name||!college||password.length<10){
    throw new Error("Role, name, valid email, ID and a password of at least 10 characters are required.");
  }

  // The auth.users INSERT trigger cannot reliably inspect app_metadata passed
  // to createUser. Authorize this one creation through a private, expiring ticket.
  const {error:ticketError}=await db.from("offline_provisioning_tickets").upsert({
    email,
    expires_at:new Date(Date.now()+5*60*1000).toISOString(),
  },{onConflict:"email"});
  if(ticketError)throw new Error("Could not authorize account provisioning: "+ticketError.message);

  let userId:string|undefined;
  try{
    const {data,error}=await db.auth.admin.createUser({
      email,
      password,
      email_confirm:true,
      user_metadata:{full_name:name,college_id:college},
    });
    if(error||!data.user)throw new Error(error?.message||"Could not create account.");
    userId=data.user.id;

    // Set trusted application metadata after the INSERT trigger has completed.
    const {error:metadataError}=await db.auth.admin.updateUserById(userId,{
      app_metadata:{offline_provisioned:true,offline_role:role},
    });
    if(metadataError)throw new Error("Account created but role metadata could not be set: "+metadataError.message);

    const {error:profileError}=await db.from("offline_profiles").upsert({
      id:userId,email,full_name:name,college_id:college,role,account_status:"active",
    },{onConflict:"id"});
    if(profileError)throw new Error("Account created but profile setup failed: "+profileError.message);

    return{id:userId,email,full_name:name,college_id:college,role,account_status:"active",initial_password:password};
  }catch(e){
    // Avoid leaving an Auth identity that has no matching OffLine profile.
    if(userId){
      const {error:deleteError}=await db.auth.admin.deleteUser(userId);
      if(deleteError)console.error("offline-admin account rollback failed",deleteError.message);
    }
    throw e;
  }finally{
    const {error:cleanupError}=await db.from("offline_provisioning_tickets").delete().eq("email",email);
    if(cleanupError)console.error("offline-admin provisioning ticket cleanup failed",cleanupError.message);
  }
}

async function getDashboard(){const a=await Promise.all([db.from("offline_profiles").select("id,email,full_name,college_id,role,account_status,created_at").order("created_at",{ascending:false}),db.from("offline_works").select("*").order("name"),db.from("offline_windows").select("*").order("name"),db.from("offline_slots").select("*").gte("slot_date",dateIST(new Date())).order("starts_at").limit(1200),db.from("offline_tokens").select("*").order("booked_at",{ascending:false}).limit(1000),db.from("offline_break_requests").select("*").order("requested_at",{ascending:false})]);const bad=a.find(x=>x.error);if(bad?.error)throw new Error(bad.error.message);return{users:a[0].data||[],services:a[1].data||[],windows:a[2].data||[],slots:a[3].data||[],tokens:a[4].data||[],breaks:a[5].data||[]};}

async function seedDemo() {
  const definitions = [
    {role:"student",full_name:"Aanya Sharma",college_id:"OFF-STU-001",email:"aanya.sharma@offline.edu"},
    {role:"student",full_name:"Rohan Verma",college_id:"OFF-STU-002",email:"rohan.verma@offline.edu"},
    {role:"staff",full_name:"Meera Kapoor",college_id:"OFF-STF-001",email:"meera.kapoor@offline.edu"},
    {role:"staff",full_name:"Arjun Malhotra",college_id:"OFF-STF-002",email:"arjun.malhotra@offline.edu"},
  ];
  const users=[];
  const demoPasswords = {
    "OFF-STU-001":"Aanya@OffLine26!",
    "OFF-STU-002":"Rohan@OffLine26!",
    "OFF-STF-001":"Meera@OffLine26!",
    "OFF-STF-002":"Arjun@OffLine26!",
  };
  for (const item of definitions) {
    const password=demoPasswords[item.college_id];
    const {data:existing,error:existingError}=await db.from("offline_profiles").select("id").eq("email",item.email).maybeSingle();
    if(existingError)throw new Error(existingError.message);
    let id="";
    if (existing?.id) {
      id=existing.id;
      const {error}=await db.auth.admin.updateUserById(id,{password,app_metadata:{offline_provisioned:true,offline_role:item.role},user_metadata:{full_name:item.full_name,college_id:item.college_id}});
      if(error)throw new Error(error.message);
      const {error:profileError}=await db.from("offline_profiles").update({full_name:item.full_name,college_id:item.college_id,role:item.role,account_status:"active"}).eq("id",id);
      if(profileError)throw new Error(profileError.message);
    } else {
      const created=await createUser({...item,password});
      id=created.id;
    }
    users.push({...item,id,password,account_status:"active"});
  }
  const {data:windows,error:windowError}=await db.from("offline_windows").select("id,name").order("name");
  if(windowError)throw new Error(windowError.message);
  const w1=windows?.find(w=>w.name.includes("Window 01"))||windows?.[0];
  const w2=windows?.find(w=>w.name.includes("Window 02"))||windows?.[1];
  const staff1=users.find(u=>u.college_id==="OFF-STF-001"),staff2=users.find(u=>u.college_id==="OFF-STF-002");
  if(w1&&staff1){
    const {error}=await db.from("offline_windows").update({staff_id:staff1.id}).eq("id",w1.id);
    if(error)throw new Error("Could not assign the first staff member: "+error.message);
  }
  if(w2&&staff2){
    const {error}=await db.from("offline_windows").update({staff_id:staff2.id}).eq("id",w2.id);
    if(error)throw new Error("Could not assign the second staff member: "+error.message);
  }
  const {count,error:countError}=await db.from("offline_tokens").select("id",{count:"exact",head:true});
  if(countError)throw new Error(countError.message);
  if((count||0)===0&&w1){
    const {data:slots,error:slotError}=await db.from("offline_slots").select("*").eq("window_id",w1.id).gt("starts_at",new Date().toISOString()).order("starts_at").limit(3);
    if(slotError)throw new Error(slotError.message);
    const students=users.filter(u=>u.role==="student");
    if(slots?.length&&students.length===2){
      const {error}=await db.from("offline_tokens").insert([
        {student_id:students[0].id,slot_id:slots[0].id,window_id:w1.id,token_number:1,queue_position:1,status:"arrived",arrived_at:new Date().toISOString()},
        {student_id:students[1].id,slot_id:slots[0].id,window_id:w1.id,token_number:2,queue_position:2,status:"booked"},
        {student_id:students[0].id,slot_id:(slots[1]||slots[0]).id,window_id:w1.id,token_number:3,queue_position:1,status:"booked"},
      ]);
      if(error)throw new Error(error.message);
    }
  }
  return {users,message:"Sample students, staff, assignments and queue records are ready."};
}

Deno.serve(async(req:Request)=>{if(req.method==="OPTIONS")return new Response("ok",{headers:cors});if(req.method!=="POST")return out({error:"Method not allowed"},405);let b:Record<string,unknown>;try{b=await req.json();}catch{return out({error:"Invalid request"},400);}const action=txt(b.action,60);try{
if(action==="login"){const pass=typeof b.passcode==="string"?b.passcode.trim():"";if(!pass)return out({error:"Passcode required"},400);const ip=txt(req.headers.get("cf-connecting-ip")||req.headers.get("x-forwarded-for")||"unknown",140),ipHash=await hash("offline-admin:"+ip);const {data:attempt}=await db.from("offline_admin_login_attempts").select("*").eq("ip_hash",ipHash).maybeSingle();if(attempt?.locked_until&&new Date(attempt.locked_until).getTime()>Date.now())return out({error:"Too many attempts. Try later."},429);const {data:cred,error}=await db.from("offline_admin_credentials").select("*").eq("id","primary").maybeSingle();const valid=!error&&cred?.active&&(await hash(pass))===String(cred.passcode_hash||"");if(!valid){const now=new Date(),start=attempt?.window_started_at?new Date(attempt.window_started_at):now,fresh=now.getTime()-start.getTime()<900000,n=fresh?Number(attempt?.attempts||0)+1:1;await db.from("offline_admin_login_attempts").upsert({ip_hash:ipHash,attempts:n,window_started_at:fresh?start.toISOString():now.toISOString(),locked_until:n>=7?new Date(now.getTime()+900000).toISOString():null},{onConflict:"ip_hash"});return out({error:"Invalid admin passcode"},401);}await db.from("offline_admin_login_attempts").delete().eq("ip_hash",ipHash);const token=rand(),expiry=new Date(Date.now()+43200000).toISOString(),{error:e}=await db.from("offline_admin_sessions").insert({token_hash:await hash(token),expires_at:expiry});if(e)return out({error:e.message},500);return out({session_token:token,expires_at:expiry});}
const s=await isAdmin(req);if(!s)return out({error:"Admin session expired. Sign in again."},401);
if(action==="logout"){await db.from("offline_admin_sessions").update({revoked_at:new Date().toISOString()}).eq("token_hash",await hash(req.headers.get("x-admin-session")||""));return out({ok:true});}
if(action==="dashboard")return out(await getDashboard());
if(action==="seed_demo")return out(await seedDemo());
if(action==="create_user")return out({user:await createUser(b)});
if(action==="update_user"){const id=txt(b.id,80);if(!id)return out({error:"User ID required"},400);const p:Record<string,unknown>={};if(b.full_name!==undefined)p.full_name=txt(b.full_name,120);if(b.college_id!==undefined)p.college_id=txt(b.college_id,80);if(b.account_status==="active"||b.account_status==="inactive")p.account_status=b.account_status;if(b.role==="student"||b.role==="staff")p.role=b.role;const {data,error}=await db.from("offline_profiles").update(p).eq("id",id).select("*").single();if(error)return out({error:error.message},400);const {error:e}=await db.auth.admin.updateUserById(id,{app_metadata:{offline_provisioned:true,offline_role:data.role},user_metadata:{full_name:data.full_name,college_id:data.college_id}});if(e)return out({error:e.message},400);return out({user:data});}
if(action==="reset_password"){const id=txt(b.id,80),password=typeof b.password==="string"?b.password:"";if(!id||password.length<10)return out({error:"Password must be at least 10 characters"},400);const {error}=await db.auth.admin.updateUserById(id,{password});if(error)return out({error:error.message},400);return out({ok:true});}
if(action==="save_service"){const id=txt(b.id,80),name=txt(b.name,100);if(!name)return out({error:"Service name required"},400);const vals={name,description:txt(b.description,500),avg_service_minutes:Math.min(45,Math.max(1,Number(b.avg_service_minutes)||10)),active:b.active!==false};const q=id?db.from("offline_works").update(vals).eq("id",id):db.from("offline_works").insert(vals);const {data,error}=await q.select("*").single();if(error)return out({error:error.message},400);return out({service:data});}
if(action==="save_window"){const id=txt(b.id,80),name=txt(b.name,120),work_id=txt(b.work_id,80);if(!name||!work_id)return out({error:"Window name and service required"},400);const vals={name,work_id,location:txt(b.location,160)||"Administrative Block",staff_id:txt(b.staff_id,80)||null};if(id){const {data,error}=await db.from("offline_windows").update(vals).eq("id",id).select("*").single();if(error)return out({error:error.message},400);return out({window:data});}const {data:work,error:we}=await db.from("offline_works").select("avg_service_minutes").eq("id",work_id).single();if(we)return out({error:we.message},400);const {data:win,error}=await db.from("offline_windows").insert({...vals,status:"open"}).select("*").single();if(error)return out({error:error.message},400);const rows=makeSlots(win.id,work.avg_service_minutes),{error:se}=await db.from("offline_slots").insert(rows);if(se)return out({error:"Window created, but slot generation failed: "+se.message},500);return out({window:win,slots_created:rows.length});}
if(action==="set_window_status"){const id=txt(b.id,80),status=["open","closed","break"].includes(String(b.status))?String(b.status):"";if(!id||!status)return out({error:"Window and status required"},400);const {data,error}=await db.from("offline_windows").update({status}).eq("id",id).select("*").single();if(error)return out({error:error.message},400);return out({window:data});}
if(action==="decide_break"){
  const id=txt(b.id,80),status=b.status==="approved"?"approved":b.status==="rejected"?"rejected":"";
  if(!id||!status)return out({error:"Invalid decision"},400);
  const {data:request,error:lookupError}=await db.from("offline_break_requests").select("id,window_id,status").eq("id",id).single();
  if(lookupError)return out({error:lookupError.message},404);
  if(request.status!=="pending")return out({error:"This break request has already been reviewed."},409);
  let priorWindowStatus:string|undefined;
  if(status==="approved"){
    const {data:window,error:windowReadError}=await db.from("offline_windows").select("status").eq("id",request.window_id).single();
    if(windowReadError)return out({error:windowReadError.message},400);
    priorWindowStatus=window.status;
    const {error:windowUpdateError}=await db.from("offline_windows").update({status:"break"}).eq("id",request.window_id);
    if(windowUpdateError)return out({error:"Could not pause the service window: "+windowUpdateError.message},500);
  }
  const {data,error}=await db.from("offline_break_requests").update({status,reviewed_at:new Date().toISOString()}).eq("id",id).eq("status","pending").select("*").single();
  if(error){
    if(status==="approved"&&priorWindowStatus){
      const {error:rollbackError}=await db.from("offline_windows").update({status:priorWindowStatus}).eq("id",request.window_id);
      if(rollbackError)console.error("offline-admin break rollback failed",rollbackError.message);
    }
    return out({error:error.message},409);
  }
  return out({break_request:data});
}
return out({error:"Unknown admin action"},400);
}catch(e){console.error("offline-admin",e instanceof Error?e.message:String(e));return out({error:e instanceof Error?e.message:"Unexpected server error"},500);}});

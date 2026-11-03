- Dependencies and the repository page show whether each package can be updated: a Status
  column with Up to date, Update within range (patch or minor), Major update or Blocked, and
  groups for Can update now, Needs a manifest change and Blocked. The repository page shows the
  newest version you can use now next to the newest version, and for a blocked package what holds
  it back and what to update first, such as "Held at 18.3.1 by react-dom, which asks for ^18.3.1.
  Update react-dom to 19.1.0 first." or "6.0.0 needs Node ^18.0.0 || >=20.0.0; the repository
  uses Node 16."
- The fix line of a vulnerability says whether the fix is within range, needs a manifest change,
  or is blocked, and what to update first. Copied repository text and notifications say the same.
- The sidebar badge of Dependencies counts only updates you can take now and security fixes.
- New setting in Settings, General: new-version notifications only for updates you can take now
  (on by default).

; Written by prodbyichigo 24/06/2026
; Functions to interact with pixels 
; Used for nm_Reset() in light of changes
; These are not specifically game related so I have moved them here.

AverageColorFromImage(pBM)
{
    Gdip_GetImageDimensions(pBM,&W,&H)
    Gdip_LockBits(pBM,0,0,W,H,&Stride,&Scan,&BD)

    r:=g:=b:=0,p:=Scan

    Loop H
	{
        x:=p
        Loop W 
		{
            c:=NumGet(x,"UInt")
            r+=(c>>16)&255,g+=(c>>8)&255,b+=c&255
            x+=4
        }
        p+=Stride
    }

    Gdip_UnlockBits(pBM,BD)

    n:=W*H
    return 0xFF000000 | (Round(r/n)<<16) | (Round(g/n)<<8) | Round(b/n)
}

ARGBToHSV(c)
{
    r := ((c>>16)&255)/255
    g := ((c>>8)&255)/255
    b := (c&255)/255

    mx := Max(r,g,b)
    mn := Min(r,g,b)
    d := mx - mn

    h := d ? (mx=r ? 60*Mod((g-b)/d,6) : mx=g ? 60*((b-r)/d+2) : 60*((r-g)/d+4)) : 0

    if (h < 0)
        h += 360

    s := mx ? d/mx*100 : 0
    v := mx*100

    return {h:h, s:s, v:v}
}

isBrown(h, s, v)
{
    ; h = 0-360
    ; s = 0-100
    ; v = 0-100

    return (
        h >= 20 && h <= 55    ; orange/yellowbrown hue
        && s >= 50            ;  saturated
        && v >= 20 && v <= 85 ; not too bright
    )
}
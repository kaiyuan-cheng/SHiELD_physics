!> \defgroup SAMF Scale-Aware Mass-Flux Deep Convection
!! @{
!!  \brief The scale-aware mass-flux (SAMF) deep convection scheme is an updated version of the previous Simplified Arakawa-Schubert (SAS) scheme with scale and aerosol awareness and parameterizes the effect of deep convection on the environment (represented by the model state variables) in the following way. First, a simple cloud model is used to determine the change in model state variables due to one entraining/detraining cloud type, per unit cloud-base mass flux. Next, the total change in state variables is retrieved by determining the actual cloud base mass flux using the quasi-equilibrium assumption (for grid sizes larger than a threshold value [currently set to 8 km]) or a mean updraft velocity (for grid sizes smaller than the threshold value). With a scale-aware parameterization, the cloud mass flux decreases with increasing grid resolution. A simple aerosol-aware parameterization is employed, where rain conversion in the convective updraft is modified by aerosol number concentration. The name SAS is replaced with SAMF as for the smaller grid sizes, the parameterization does not use Arakawa-Schubert's quasi-equilibrium assumption any longer where the cloud work function (interpreted as entrainment-moderated convective available potential energy [CAPE]) by the large scale dynamics is in balance with the consumption of the cloud work function by the convection.
!!
!!  The SAS scheme uses the working concepts put forth in Arakawa and Schubert (1974) \cite arakawa_and_schubert_1974 but includes modifications and simplifications from Grell (1993) \cite grell_1993 such as saturated downdrafts and only one cloud type (the deepest possible), rather than a spectrum based on cloud top heights or assumed entrainment rates. The scheme was implemented for the GFS in 1995 by Pan and Wu \cite pan_and_wu_1995, with further modifications discussed in Han and Pan (2011) \cite han_and_pan_2011 , including the calculation of cloud top, a greater CFL-criterion-based maximum cloud base mass flux, updated cloud model entrainment and detrainment, improved convective transport of horizontal momentum, a more general triggering function, and the inclusion of convective overshooting.
!!
!! The SAMF scheme updates the SAS scheme with scale- and aerosol-aware parameterizations from Han et al. (2017) \cite han_et_al_2017 based on the studies by Arakawa and Wu (2013) \cite arakawa_and_wu_2013 and Grell and Freitas (2014) \cite grell_and_freitus_2014 for scale awareness and by Lim (2011) \cite lim_2011 for aerosol awareness. The ratio of advective time to convective turnover time is also taken into account for the scale-aware parameterization. Along with the scale- and aerosol-aware parameterizations, more changes are made to the SAMF scheme. The cloud base mass-flux computation is modified to use convective turnover time as the convective adjustment time scale. The rain conversion rate is modified to decrease with decreasing air temperature above the freezing level. Convective inhibition in the sub-cloud layer is used as an additional trigger condition. Convective cloudiness is enhanced by considering suspended cloud condensate in the updraft. The lateral entrainment is also enhanced to more strongly suppress convection in a drier environment.
!!
!! In further update for FY19 GFS implementation, interaction with turbulent kinetic energy (TKE), which is a prognostic variable used in a scale-aware TKE-based moist EDMF vertical turbulent mixing scheme, is included. Entrainment rates in updrafts and downdrafts are proportional to sub-cloud mean TKE. TKE is transported by cumulus convection. TKE contribution from cumulus convection is deduced from cumulus mass flux. On the other hand, tracers such as ozone and aerosol are also transported by cumulus convection.
!!
!! Occasional model crashes have been occurred when stochastic physics is on, due to too much convective cooling and heating tendencies near the cumulus top which are amplified by stochastic physics. To reduce too much convective cooling at the cloud top, the convection schemes have been modified for the rain conversion rate, entrainment and detrainment rates, overshooting layers, and maximum allowable cloudbase mass flux (as of June 2018). 
!!
!!  \section diagram Calling Hierarchy Diagram
!!  \image html SAMF_Flowchart.png "Diagram depicting how the SAMF deep convection scheme is called from the FV3GFS physics time loop" height=2cm
!!  \section intraphysics Intraphysics Communication
!!  This space is reserved for a description of how this scheme uses information from other scheme types and/or how information calculated in this scheme is used in other scheme types.

!> \file samfdeepcnv.f
!!  Contains the entire SAMF deep convection scheme.

!>  \brief This subroutine contains the entirety of the SAMF deep convection scheme.
!!
!!  For grid sizes larger than threshold value, as in Grell (1993) \cite grell_1993 , the SAMF deep convection scheme can be described in terms of three types of "controls": static, dynamic, and feedback. The static control component consists of the simple entraining/detraining updraft/downdraft cloud model and is used to determine the cloud properties, convective precipitation, as well as the convective cloud top height. The dynamic control is the determination of the potential energy available for convection to "consume", or how primed the large-scale environment is for convection to occur due to changes by the dyanmics of the host model. The feedback control is the determination of how the parameterized convection changes the large-scale environment (the host model state variables) given the changes to the state variables per unit cloud base mass flux calculated in the static control portion and the deduced cloud base mass flux determined from the dynamic control.
!!
!! For grid sizes smaller than threshold value, the cloud base mass flux in the SAMF scheme is determined by the cumulus updraft velocity averaged ove the whole cloud depth (Han et al., 2017 \cite han_et_al_2017 ), which in turn, determines changes of the large-scale environment due to the cumulus convection.
!!
!!  \param[in] im number of used points
!!  \param[in] ix horizontal dimension
!!  \param[in] km vertical layer dimension
!!  \param[in] delt physics time step in seconds
!!  \param[in] ntk index for TKE
!!  \param[in] ntr total number of tracers including TKE
!!  \param[in] delp pressure difference between level k and k+1 (Pa)
!!  \param[in] prslp mean layer presure (Pa)
!!  \param[in] psp surface pressure (Pa)
!!  \param[in] phil layer geopotential (\f$m^2/s^2\f$)
!!  \param[in] qtr tracer array including cloud condensate (\f$kg/kg\f$)
!!  \param[inout] ql cloud water or ice (kg/kg)
!!  \param[inout] q1 updated tracers (kg/kg)
!!  \param[inout] t1 updated temperature (K)
!!  \param[inout] u1 updated zonal wind (\f$m s^{-1}\f$)
!!  \param[inout] v1 updated meridional wind (\f$m s^{-1}\f$)
!!  \param[out] cldwrk cloud workfunction (\f$m^2/s^2\f$)
!!  \param[out] rn convective rain (m)
!!  \param[out] kbot index for cloud base
!!  \param[out] ktop index for cloud top
!!  \param[out] kcnv flag to denote deep convection (0=no, 1=yes)
!!  \param[in] islimsk sea/land/ice mask (=0/1/2)
!!  \param[in] garea area of grid box (\f$m^2\f$)
!!  \param[in] dot layer mean vertical velocity (Pa/s)
!!  \param[in] ncloud number of cloud species
!!  \param[out] ud_mf updraft mass flux multiplied by time step (\f$kg/m^2\f$)
!!  \param[out] dd_mf downdraft mass flux multiplied by time step (\f$kg/m^2\f$)
!!  \param[out] dt_mf ud_mf at cloud top (\f$kg/m^2\f$)
!!  \param[out] cnvw convective cloud water (kg/kg)
!!  \param[out] cnvc convective cloud cover (unitless)
!!  \param[in] clam coefficient for entrainment rate
!!  \param[in] c0s convective rain conversion parameter (1/m)
!!  \param[in] c1 conversion parameter of detrainment from liquid water into grid-scale cloud water (1/m)
!!  \param[in] betal fraction factor of downdraft air mass reaching ground surface over land
!!  \param[in] betas fraction factor of downdraft air mass reaching ground surface over sea
!!  \param[in] evfact evaporation factor from convective rain 
!!  \param[in] evfactl evaporation factor from convective rain over land
!!  \param[in] pgcon reduction factor in momentum transport due to convection induced pressure gradient force
!!  \param[in] asolfac aerosol-aware parameter inversely proportional to CCN number concentraion 
!!
!!  \section general General Algorithm
!!  -# Compute preliminary quantities needed for static, dynamic, and feedback control portions of the algorithm.
!!  -# Perform calculations related to the updraft of the entraining/detraining cloud model ("static control").
!!  -# Perform calculations related to the downdraft of the entraining/detraining cloud model ("static control").
!!
!!  -# For grid sizes larger than the threshold value (currently 8 km):
!!        + 1) Using the updated temperature and moisture profiles that were modified by the convection on a short time-scale, recalculate the total cloud work function to determine the change in the cloud work function due to convection, or the stabilizing effect of the cumulus.
!!        + 2) For the "dynamic control", using a reference cloud work function, estimate the change in cloud work function due to the large-scale dynamics. Following the quasi-equilibrium assumption, calculate the cloud base mass flux required to keep the large-scale convective destabilization in balance with the stabilization effect of the convection.
!!  -# For grid sizes smaller than the threshold value (currently 8 km):
!!        + 1) compute the cloud base mass flux using the cumulus updraft velocity averaged ove the whole cloud depth.
!!  -# For scale awareness, the updraft fraction (sigma) is obtained as a function of cloud base entrainment. Then, the final cloud base mass flux is obtained by the original mass flux multiplied by the (1sigma) 2  .
!!  -# For the "feedback control", calculate updated values of the state variables by multiplying the cloud base mass flux and the tendencies calculated per unit cloud base mass flux from the static control.
!!
!!  \section detailed Detailed Algorithm
!!  @{
      subroutine samfdeepcnv(im,ix,km,delt,itc,ntc,ntk,ntr,delp,
     &     prslp,psp,phil,qtr,q1,t1,u1,v1,fscav,
     &     do_ca,ca_deep,cldwrk,rn,kbot,ktop,kcnv,islimsk,garea,
     &     dot,ncloud,ud_mf,dd_mf,dt_mf,cnvw,cnvc,
     &     QLCN, QICN, w_upi, cf_upi, CNV_MFD,
!    &     QLCN, QICN, w_upi, cf_upi, CNV_MFD, CNV_PRC3,
     &     CNV_DQLDT,CLCN,CNV_FICE,CNV_NDROP,CNV_NICE,mp_phys,
     &     clam,c0s,c1,betal,betas,evfact,evfactl,pgcon,asolfac,dxcrtas,
     &     use_tke_conv,use_shear_conv)
!
      use machine , only : kind_phys
      use funcphys , only : fpvs
      use physcons, grav => con_g,  cp    => con_cp,    hvap => con_hvap
     &,             rv   => con_rv, fv    => con_fvirt, t0c  => con_t0c
     &,             rd   => con_rd, cvap  => con_cvap,  cliq => con_cliq
     &,             eps  => con_eps,epsm1 => con_epsm1
      implicit none
!
      integer, intent(in)  :: im, ix, km, itc, ntc, ntk, ntr, ncloud
      integer, intent(in)  :: islimsk(im)
      real(kind=kind_phys), intent(in) ::  delt
      real(kind=kind_phys), intent(in) :: psp(im), delp(ix,km), 
     &   prslp(ix,km),  garea(im), dot(ix,km), phil(ix,km) 
      real(kind=kind_phys), intent(in) :: fscav(ntc)
      real(kind=kind_phys), intent(in) :: ca_deep(ix)
      logical, intent(in)  :: do_ca
      integer, intent(inout)  :: kcnv(im)        
      real(kind=kind_phys), intent(inout) ::   qtr(ix,km,ntr+2),
     &   q1(ix,km), t1(ix,km),   u1(ix,km), v1(ix,km)

      integer, intent(out) :: kbot(im), ktop(im) 
      real(kind=kind_phys), intent(out) :: cldwrk(im), 
     &   rn(im),      cnvw(ix,km),  cnvc(ix,km),
     &   ud_mf(im,km),dd_mf(im,km), dt_mf(im,km)

      real(kind=kind_phys) clam,    c0s,     c1,
     &                     betal,   betas,   asolfac,
     &                     evfact,  evfactl, pgcon
!
!------local variables

      logical              use_tke_conv, use_shear_conv
      integer              i, indx, jmn, k, kk, km1, n
!     integer              latd,lond
!
      real(kind=kind_phys) clamd,   tkemx,   tkemn,   dtke,
     &                     beta,    dbeta,   betamx,  betamn,
     &                     cxlame,  cxlamd,
     &                     xlamde,  xlamdd,
     &                     crtlame, crtlamd
! 
!     real(kind=kind_phys) detad
      real(kind=kind_phys) adw,     aup,     aafac,   d0,
     &                     dellat,  delta,   desdt,   dg,
     &                     dh,      dhh,     dp,
     &                     dq,      dqsdp,   dqsdt,   dt,
     &                     dt2,     dtmax,   dtmin,   
     &                     dxcrtas, dxcrtuf, 
     &                     dv1h,    dv2h,    dv3h,
     &                     dv1q,    dv2q,    dv3q,
     &                     dz,      dz1,     e1,      edtmax,
     &                     edtmaxl, edtmaxs, el2orc,  elocp,
     &                     es,      etah,
     &                     cthk,    dthk,
     &                     evef,    fact1,   fact2,   factor,
     &                     g,       gamma,   pprime,  cm,
     &                     qlk,     qrch,    qs,
     &                     rain,    rfact,   shear,   tfac,
     &                     val,     val1,    val2,
     &                     w1,      w1l,     w1s,     w2,
     &                     w2l,     w2s,     w3,      w3l,
     &                     w3s,     w4,      w4l,     w4s,
     &                     rho,     betaw,
     &                     xdby,    xpw,     xpwd,
!    &                     xqrch,   mbdt,    tem,
     &                     xqrch,   tem,     tem1,    tem2,
     &                     ptem,    ptem1,   ptem2
!
      integer              kb(im), kbcon(im), kbcon1(im),
     &                     ktcon(im), ktcon1(im), ktconn(im),
     &                     jmin(im), lmin(im), kbmax(im),
     &                     kbm(im), kmax(im)
!
!     real(kind=kind_phys) aa1(im),     acrt(im),   acrtfct(im),
      real(kind=kind_phys) aa1(im),     tkemean(im),clamt(im),
     &                     ps(im),      del(ix,km), prsl(ix,km),
     &                     umean(im),   tauadv(im), gdx(im),
     &                     delhbar(im), delq(im),   delq2(im),
     &                     delqbar(im), delqev(im), deltbar(im),
     &                     deltv(im),   dtconv(im), edt(im),
     &                     edto(im),    edtx(im),   fld(im),
     &                     hcdo(im,km), hmax(im),   hmin(im), 
     &                     ucdo(im,km), vcdo(im,km),aa2(im),
     &                     ecdo(im,km,ntr),
     &                     pdot(im),    po(im,km),
     &                     pwavo(im),   pwevo(im),  mbdt(im),
     &                     qcdo(im,km), qcond(im),  qevap(im),
     &                     rntot(im),   vshear(im), xaa0(im),
     &                     xlamd(im),   xk(im),     cina(im),
     &                     xmb(im),     xmbmax(im), xpwav(im),
!    &                     xpwev(im),   xlamx(im),  delebar(im,ntr),
     &                     xpwev(im),   delebar(im,ntr),
     &                     delubar(im), delvbar(im),
     &                     xlamdet(im), xlamddt(im),
     &                     cxlamet(im), cxlamdt(im)
!
      real(kind=kind_phys) c0(im)
cj
      real(kind=kind_phys) cinpcr,  cinpcrmx,  cinpcrmn,
     &                     cinacr,  cinacrmx,  cinacrmn
cj
!
!  parameters for updraft velocity calculation
      real(kind=kind_phys) bet1,    cd1,     f1,      gam1,
     &                     bb1,     bb2,     csmf,    tkcrt, cmxfac
!    &                     bb1,     bb2,     wucb
!
c  physical parameters
!     parameter(g=grav,asolfac=0.958)
      parameter(g=grav)
      parameter(elocp=hvap/cp,el2orc=hvap*hvap/(rv*cp))
!     parameter(c0s=.002,c1=.002,d0=.01)
!     parameter(d0=.01)
      parameter(d0=.001)
!     parameter(c0l=c0s*asolfac)
!
! asolfac: aerosol-aware parameter based on Lim (2011)
!      asolfac= cx / c0s(=.002)
!      cx = min([-0.7 ln(Nccn) + 24]*1.e-4, c0s)
!      Nccn: CCN number concentration in cm^(-3)
!      Until a realistic Nccn is provided, Nccns are assumed
!      as Nccn=100 for sea and Nccn=1000 for land 
!
      parameter(cm=1.0,delta=fv)
      parameter(fact1=(cvap-cliq)/rv,fact2=hvap/rv-fact1*t0c)
      parameter(clamd=0.03,tkemx=0.65,tkemn=0.05)
      parameter(dtke=tkemx-tkemn)
      parameter(dbeta=0.1)
      parameter(cthk=200.,dthk=25.)
      parameter(cinpcrmx=180.,cinpcrmn=120.)
!     parameter(cinacrmx=-120.,cinacrmn=-120.)
      parameter(cinacrmx=-120.,cinacrmn=-80.)
      parameter(bet1=1.875,cd1=.506,f1=2.0,gam1=.5)
      parameter(betaw=.03,dxcrtuf=15.e3)
!     parameter(dxcrtas=8.e3)
      parameter(bb1=4.0,bb2=0.8,csmf=0.2)
      parameter(tkcrt=2.,cmxfac=15.)
!
!  local variables and arrays
      real(kind=kind_phys) pfld(im,km),    to(im,km),     qo(im,km),
     &                     uo(im,km),      vo(im,km),     qeso(im,km),
     &                     ctr(im,km,ntr), ctro(im,km,ntr)
!  for aerosol transport
      real(kind=kind_phys) qaero(im,km,ntc)
!  for updraft velocity calculation
      real(kind=kind_phys) wu2(im,km),     buo(im,km),    drag(im,km),
     &                     wush(im,km)
      real(kind=kind_phys) wc(im),         scaldfunc(im), sigmagfm(im)
!
c  cloud water
!     real(kind=kind_phys) tvo(im,km)
      real(kind=kind_phys) qlko_ktcon(im), dellal(im,km), tvo(im,km),
     &                     dbyo(im,km),    zo(im,km),     
     &                     xlamue(im,km),  xlamud(im,km),
     &                     fent1(im,km),   fent2(im,km),  frh(im,km),
     &                     heo(im,km),     heso(im,km),
     &                     qrcd(im,km),    dellah(im,km), dellaq(im,km),
     &                     dellae(im,km,ntr),
     &                     dellau(im,km),  dellav(im,km), hcko(im,km),
     &                     ucko(im,km),    vcko(im,km),   qcko(im,km),
     &                     ecko(im,km,ntr),
     &                     eta(im,km),     etad(im,km),   zi(im,km),
     &                     qrcko(im,km),   qrcdo(im,km),
     &                     pwo(im,km),     pwdo(im,km),   c0t(im,km),
     &                     tx1(im),        sumx(im),      cnvwt(im,km)
!    &,                    rhbar(im)
!
      real(kind=kind_phys), dimension(im,km)   :: qlcn, qicn, w_upi   
     &,                                           cnv_mfd
!    &,                                           cnv_mfd, cnv_prc3    
     &,                                           cnv_dqldt, clcn       
     &,                                           cnv_fice, cnv_ndrop   
     &,                                           cnv_nice, cf_upi
      integer mp_phys
      logical do_aerosols, totflg, cnvflg(im), asqecflg(im), flg(im)
!
!    asqecflg: flag for the quasi-equilibrium assumption of Arakawa-Schubert
!
!     real(kind=kind_phys) pcrit(15), acritt(15), acrit(15)
!!    save pcrit, acritt
!     data pcrit/850.,800.,750.,700.,650.,600.,550.,500.,450.,400.,
!    &           350.,300.,250.,200.,150./
!     data acritt/.0633,.0445,.0553,.0664,.075,.1082,.1521,.2216,
!    &           .3151,.3677,.41,.5255,.7663,1.1686,1.6851/
c  gdas derived acrit
c     data acritt/.203,.515,.521,.566,.625,.665,.659,.688,
c    &            .743,.813,.886,.947,1.138,1.377,1.896/
      real(kind=kind_phys) tf, tcr, tcrf
      parameter (tf=233.16, tcr=263.16, tcrf=1.0/(tcr-tf))
!
c-----------------------------------------------------------------------
!>  ## Determine whether to perform aerosol transport
      do_aerosols = (itc > 0) .and. (ntc > 0) .and. (ntr > 0)
      if (do_aerosols) do_aerosols = (ntr >= itc + ntc - 3)
!
c-----------------------------------------------------------------------
!>  ## Compute preliminary quantities needed for static, dynamic, and feedback control portions of the algorithm.
!>  - Convert input pressure terms to centibar units.
!************************************************************************
!     convert input Pa terms to Cb terms  -- Moorthi
      ps   = psp   * 0.001
      prsl = prslp * 0.001
      del  = delp  * 0.001
!************************************************************************
!
!
      km1 = km - 1
!>  - Initialize column-integrated and other single-value-per-column variable arrays.
c
c  initialize arrays
c
      do i=1,im
        cnvflg(i) = .true.
        rn(i)=0.
        mbdt(i)=10.
        kbot(i)=km+1
        ktop(i)=0
        kbcon(i)=km
        ktcon(i)=1
        ktconn(i)=1
        dtconv(i) = 3600.
        cldwrk(i) = 0.
        pdot(i) = 0.
        lmin(i) = 1
        jmin(i) = 1
        qlko_ktcon(i) = 0.
        edt(i)  = 0.
        edto(i) = 0.
        edtx(i) = 0.
!       acrt(i) = 0.
!       acrtfct(i) = 1.
        aa1(i)  = 0.
        aa2(i)  = 0.
        xaa0(i) = 0.
        cina(i) = 0.
        pwavo(i)= 0.
        pwevo(i)= 0.
        xpwav(i)= 0.
        xpwev(i)= 0.
        vshear(i) = 0.
        gdx(i) = sqrt(garea(i))
      enddo
!
!>  - determine aerosol-aware rain conversion parameter over land
      do i=1,im
        if(islimsk(i) == 1) then
           c0(i) = c0s*asolfac
        else
           c0(i) = c0s
        endif
      enddo
!>  - determine rain conversion parameter above the freezing level which exponentially decreases with decreasing temperature from Han et al.'s (2017) \cite han_et_al_2017 equation 8.
      do k = 1, km
        do i = 1, im
          if(t1(i,k) > 273.16) then
            c0t(i,k) = c0(i)
          else
            tem = d0 * (t1(i,k) - 273.16)
            tem1 = exp(tem)
            c0t(i,k) = c0(i) * tem1
          endif
        enddo
      enddo
!>  - Initialize convective cloud water and cloud cover to zero.
      do k = 1, km
        do i = 1, im
          cnvw(i,k) = 0.
          cnvc(i,k) = 0.
        enddo
      enddo
! hchuang code change
!>  - Initialize updraft and downdraft mass fluxes to zero.
      do k = 1, km
        do i = 1, im
          ud_mf(i,k) = 0.
          dd_mf(i,k) = 0.
          dt_mf(i,k) = 0.
        enddo
      enddo
      if(mp_phys == 10) then
        do k = 1, km
          do i = 1, im
            QLCN(i,k)      = qtr(i,k,2)
            QICN(i,k)      = qtr(i,k,1)
            w_upi(i,k)     = 0.0
            cf_upi(i,k)    = 0.0
            CNV_MFD(i,k)   = 0.0

            CNV_DQLDT(i,k) = 0.0
            CLCN(i,k)      = 0.0
            CNV_FICE(i,k)  = 0.0
            CNV_NDROP(i,k) = 0.0
            CNV_NICE(i,k)  = 0.0
          enddo
        enddo
      endif
c
!     do k = 1, 15
!       acrit(k) = acritt(k) * (975. - pcrit(k))
!     enddo
!
      dt2 = delt
!     val   =         1200.
      val   =         600.
      dtmin = max(dt2, val )
!     val   =         5400.
      val   =         10800.
      dtmax = max(dt2, val )
!  model tunable parameters are all here
      edtmaxl = .3
      edtmaxs = .3
!     clam    = .1
!     aafac   = .1
      aafac   = .05
!     betal   = .15
!     betas   = .15
!     betal   = .05
!     betas   = .05
!     evef    = 0.07
!     evfact  = 0.3
!     evfactl = 0.3
!
      crtlame = 1.0e-4
      crtlamd = 1.0e-4
!
!     cxlame  = 1.0e-3
      cxlame  = 1.0e-4
      cxlamd  = 1.0e-4
      xlamde  = 1.0e-4
      xlamdd  = 1.0e-4
!
!     pgcon   = 0.7     ! Gregory et al. (1997, QJRMS)
!     pgcon   = 0.55    ! Zhang & Wu (2003,JAS)
!
      w1l     = -8.e-3 
      w2l     = -4.e-2
      w3l     = -5.e-3 
      w4l     = -5.e-4
      w1s     = -2.e-4
      w2s     = -2.e-3
      w3s     = -1.e-3
      w4s     = -2.e-5
c
c  define top layer for search of the downdraft originating layer
c  and the maximum thetae for updraft
c
!>  - Determine maximum indices for the parcel starting point (kbm), LFC (kbmax), and cloud top (kmax).
      do i=1,im
        kbmax(i) = km
        kbm(i)   = km
        kmax(i)  = km
        tx1(i)   = 1.0 / ps(i)
      enddo
!     
      do k = 1, km
        do i=1,im
          if (prsl(i,k)*tx1(i) > 0.04) kmax(i)  = k + 1
          if (prsl(i,k)*tx1(i) > 0.45) kbmax(i) = k + 1
          if (prsl(i,k)*tx1(i) > 0.70) kbm(i)   = k + 1
        enddo
      enddo
      do i=1,im
        kmax(i)  = min(km,kmax(i))
        kbmax(i) = min(kbmax(i),kmax(i))
        kbm(i)   = min(kbm(i),kmax(i))
      enddo
c
c  hydrostatic height assume zero terr and initially assume
c    updraft entrainment rate as an inverse function of height 
c
!>  - Calculate hydrostatic height at layer centers assuming a flat surface (no terrain) from the geopotential.
      do k = 1, km
        do i=1,im
          zo(i,k) = phil(i,k) / g
        enddo
      enddo
!>  - Calculate interface height
      do k = 1, km1
        do i=1,im
          zi(i,k) = 0.5*(zo(i,k)+zo(i,k+1))
        enddo
      enddo
c
c!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
c   convert surface pressure to mb from cb
c
!>  - Convert prsl from centibar to millibar, set normalized mass fluxes to 1, cloud properties to 0, and save model state variables (after advection/turbulence).
      do k = 1, km
        do i = 1, im
          if (k <= kmax(i)) then
            pfld(i,k) = prsl(i,k) * 10.0
            eta(i,k)  = 1.
            fent1(i,k)= 1.
            fent2(i,k)= 1.
            frh(i,k)  = 0.
            hcko(i,k) = 0.
            qcko(i,k) = 0.
            qrcko(i,k)= 0.
            ucko(i,k) = 0.
            vcko(i,k) = 0.
            etad(i,k) = 1.
            hcdo(i,k) = 0.
            qcdo(i,k) = 0.
            ucdo(i,k) = 0.
            vcdo(i,k) = 0.
            qrcd(i,k) = 0.
            qrcdo(i,k)= 0.
            dbyo(i,k) = 0.
            pwo(i,k)  = 0.
            pwdo(i,k) = 0.
            dellal(i,k) = 0.
            to(i,k)   = t1(i,k)
            qo(i,k)   = q1(i,k)
            uo(i,k)   = u1(i,k)
            vo(i,k)   = v1(i,k)
!           uo(i,k)   = u1(i,k) * rcs(i)
!           vo(i,k)   = v1(i,k) * rcs(i)
            wu2(i,k)  = 0.
            buo(i,k)  = 0.
            drag(i,k) = 0.
            cnvwt(i,k)= 0.
          endif
        enddo
      enddo
!
!  initialize tracer variables
!
      do n = 3, ntr+2
        kk = n-2
        do k = 1, km
          do i = 1, im
            if (k <= kmax(i)) then
              ctr(i,k,kk)  = qtr(i,k,n)
              ctro(i,k,kk) = qtr(i,k,n)
              ecko(i,k,kk) = 0.
              ecdo(i,k,kk) = 0.
            endif
          enddo
        enddo
      enddo
!
!>  - Calculate saturation specific humidity and enforce minimum moisture values.
      do k = 1, km
        do i=1,im
          if (k <= kmax(i)) then
            qeso(i,k) = 0.01 * fpvs(to(i,k))      ! fpvs is in pa
            qeso(i,k) = eps * qeso(i,k) / (pfld(i,k) + epsm1*qeso(i,k))
            val1      =             1.e-8
            qeso(i,k) = max(qeso(i,k), val1)
            val2      =           1.e-10
            qo(i,k)   = max(qo(i,k), val2 )
!           qo(i,k)   = min(qo(i,k),qeso(i,k))
!           tvo(i,k)  = to(i,k) + delta * to(i,k) * qo(i,k)
          endif
        enddo
      enddo
c
c  compute moist static energy
c
!>  - Calculate moist static energy (heo) and saturation moist static energy (heso).
      do k = 1, km
        do i=1,im
          if (k <= kmax(i)) then
!           tem       = g * zo(i,k) + cp * to(i,k)
            tem       = phil(i,k) + cp * to(i,k)
            heo(i,k)  = tem  + hvap * qo(i,k)
            heso(i,k) = tem  + hvap * qeso(i,k)
c           heo(i,k)  = min(heo(i,k),heso(i,k))
          endif
        enddo
      enddo
c
c  determine level with largest moist static energy
c  this is the level where updraft starts
c
!> ## Perform calculations related to the updraft of the entraining/detraining cloud model ("static control").
!> - Search below index "kbm" for the level of maximum moist static energy.
      do i=1,im
        hmax(i) = heo(i,1)
        kb(i)   = 1
      enddo
      do k = 2, km
        do i=1,im
          if (k <= kbm(i)) then
            if(heo(i,k) > hmax(i)) then
              kb(i)   = k
              hmax(i) = heo(i,k)
            endif
          endif
        enddo
      enddo
c
!> - Calculate the temperature, specific humidity, and pressure at interface levels.
      do k = 1, km1
        do i=1,im
          if (k <= kmax(i)-1) then
            dz      = .5 * (zo(i,k+1) - zo(i,k))
            dp      = .5 * (pfld(i,k+1) - pfld(i,k))
            es      = 0.01 * fpvs(to(i,k+1))      ! fpvs is in pa
            pprime  = pfld(i,k+1) + epsm1 * es
            qs      = eps * es / pprime
            dqsdp   = - qs / pprime
            desdt   = es * (fact1 / to(i,k+1) + fact2 / (to(i,k+1)**2))
            dqsdt   = qs * pfld(i,k+1) * desdt / (es * pprime)
            gamma   = el2orc * qeso(i,k+1) / (to(i,k+1)**2)
            dt      = (g * dz + hvap * dqsdp * dp) / (cp * (1. + gamma))
            dq      = dqsdt * dt + dqsdp * dp
            to(i,k) = to(i,k+1) + dt
            qo(i,k) = qo(i,k+1) + dq
            po(i,k) = .5 * (pfld(i,k) + pfld(i,k+1))
          endif
        enddo
      enddo
!
!> - Recalculate saturation specific humidity, moist static energy, saturation moist static energy, and horizontal momentum on interface levels. Enforce minimum specific humidity and calculate \f$(1 - RH)\f$.
      do k = 1, km1
        do i=1,im
          if (k <= kmax(i)-1) then
            qeso(i,k) = 0.01 * fpvs(to(i,k))      ! fpvs is in pa
            qeso(i,k) = eps * qeso(i,k) / (po(i,k) + epsm1*qeso(i,k))
            val1      =             1.e-8
            qeso(i,k) = max(qeso(i,k), val1)
            val2      =           1.e-10
            qo(i,k)   = max(qo(i,k), val2 )
!           qo(i,k)   = min(qo(i,k),qeso(i,k))
            tem = min(qo(i,k)/qeso(i,k), 1.)
            frh(i,k)  = 1. - tem
            heo(i,k)  = .5 * g * (zo(i,k) + zo(i,k+1)) +
     &                  cp * to(i,k) + hvap * qo(i,k)
            heso(i,k) = .5 * g * (zo(i,k) + zo(i,k+1)) +
     &                  cp * to(i,k) + hvap * qeso(i,k)
            uo(i,k)   = .5 * (uo(i,k) + uo(i,k+1))
            vo(i,k)   = .5 * (vo(i,k) + vo(i,k+1))
          endif
        enddo
      enddo
      do n = 1, ntr
      do k = 1, km1
        do i=1,im
          if (k <= kmax(i)-1) then
            ctro(i,k,n) = .5 * (ctro(i,k,n) + ctro(i,k+1,n))
          endif
        enddo
      enddo
      enddo
c
c  look for the level of free convection as cloud base
c
!> - Search below the index "kbmax" for the level of free convection (LFC) where the condition \f$h_b > h^*\f$ is first met, where \f$h_b, h^*\f$ are the state moist static energy at the parcel's starting level and saturation moist static energy, respectively. Set "kbcon" to the index of the LFC.
      do i=1,im
        flg(i)   = .true.
        kbcon(i) = kmax(i)
      enddo
      do k = 1, km1
        do i=1,im
          if (flg(i) .and. k <= kbmax(i)) then
            if(k > kb(i) .and. heo(i,kb(i)) > heso(i,k)) then
              kbcon(i) = k
              flg(i)   = .false.
            endif
          endif
        enddo
      enddo
c
!> - If no LFC, return to the calling routine without modifying state variables.
      do i=1,im
        if(kbcon(i) == kmax(i)) cnvflg(i) = .false.
      enddo
!!
      totflg = .true.
      do i=1,im
        totflg = totflg .and. (.not. cnvflg(i))
      enddo
      if(totflg) return
!!
!> - Determine the vertical pressure velocity at the LFC. After Han and Pan (2011) \cite han_and_pan_2011 , determine the maximum pressure thickness between a parcel's starting level and the LFC. If a parcel doesn't reach the LFC within the critical thickness, then the convective inhibition is deemed too great for convection to be triggered, and the subroutine returns to the calling routine without modifying the state variables.
      do i=1,im
        if(cnvflg(i)) then
!         pdot(i)  = 10.* dot(i,kbcon(i))
          pdot(i)  = 0.01 * dot(i,kbcon(i)) ! Now dot is in Pa/s
        endif
      enddo
c
c   turn off convection if pressure depth between parcel source level
c      and cloud base is larger than a critical value, cinpcr
c
      do i=1,im
        if(cnvflg(i)) then
          if(islimsk(i) == 1) then
            w1 = w1l
            w2 = w2l
            w3 = w3l
            w4 = w4l
          else
            w1 = w1s
            w2 = w2s
            w3 = w3s
            w4 = w4s
          endif
          if(pdot(i) <= w4) then
            tem = (pdot(i) - w4) / (w3 - w4)
          elseif(pdot(i) >= -w4) then
            tem = - (pdot(i) + w4) / (w4 - w3)
          else
            tem = 0.
          endif
          val1    =            -1.
          tem = max(tem,val1)
          val2    =             1.
          tem = min(tem,val2)
          ptem = 1. - tem
          ptem1= .5*(cinpcrmx-cinpcrmn)
          cinpcr = cinpcrmx - ptem * ptem1
          tem1 = pfld(i,kb(i)) - pfld(i,kbcon(i))
          if(tem1 > cinpcr) then
             cnvflg(i) = .false.
          endif
        endif
      enddo
!!
      totflg = .true.
      do i=1,im
        totflg = totflg .and. (.not. cnvflg(i))
      enddo
      if(totflg) return
!!
!
! turbulent entrainment rate assumed to be proportional
!   to subcloud mean TKE 
!
      if(ntk > 0) then
!
        do i= 1, im
          if(cnvflg(i)) then
            sumx(i) = 0.
            tkemean(i) = 0.
          endif
        enddo
        do k = 1, km1
          do i = 1, im
            if(cnvflg(i)) then
              if(k >= kb(i) .and. k < kbcon(i)) then
                dz = zo(i,k+1) - zo(i,k)
                tem = 0.5 * (qtr(i,k,ntk)+qtr(i,k+1,ntk))
                tkemean(i) = tkemean(i) + tem * dz
                sumx(i) = sumx(i) + dz
              endif
            endif
          enddo
        enddo
!
        do i= 1, im
          if(cnvflg(i)) then
             tkemean(i) = tkemean(i) / sumx(i)
             if(tkemean(i) > tkemx) then
               clamt(i) = clam + clamd
             else if(tkemean(i) < tkemn) then
               clamt(i) = clam - clamd
             else
               tem = tkemx - tkemean(i)
               tem1 = 1. - 2. *  tem / dtke
               clamt(i) = clam + clamd * tem1
             endif
          endif
        enddo

        ! kgao 12/08/2023: adjust ent/det rates based on tke 
        if (use_tke_conv) then
        do i=1,im
          if(cnvflg(i)) then
            xlamdet(i) = xlamde
            xlamddt(i) = xlamdd
            cxlamet(i) = cxlame
            cxlamdt(i) = cxlamd
            if(tkemean(i) > tkcrt) then
              tem = 1. + tkemean(i)/tkcrt
              tem1 = min(tem, cmxfac)
              clamt(i) = tem1 * clam
              xlamdet(i) = tem1 * xlamdet(i)
              xlamddt(i) = tem1 * xlamddt(i)
              cxlamet(i) = tem1 * cxlamet(i)
              cxlamdt(i) = tem1 * cxlamdt(i)
            endif
          endif
        enddo
        endif
!
      else
!
        do i= 1, im
          if(cnvflg(i)) then
            clamt(i)  = clam
          endif
        enddo
!
      endif
!
!  also initially assume updraft entrainment rate
!     is an inverse function of height
!
      do k = 1, km1
        do i=1,im
          if(cnvflg(i)) then
            xlamue(i,k) = clamt(i) / zi(i,k)
            xlamue(i,k) = max(xlamue(i,k), crtlame)
          endif
        enddo
      enddo
c
c  assume that updraft entrainment rate above cloud base is
c    same as that at cloud base
c
!> - Calculate the entrainment rate according to Han and Pan (2011) \cite han_and_pan_2011 , equation 8, after Bechtold et al. (2008) \cite bechtold_et_al_2008, equation 2 given by:
!!  \f[
!!  \epsilon = \epsilon_0F_0 + d_1\left(1-RH\right)F_1
!!  \f]
!!  where \f$\epsilon_0\f$ is the cloud base entrainment rate, \f$d_1\f$ is a tunable constant, and \f$F_0=\left(\frac{q_s}{q_{s,b}}\right)^2\f$ and \f$F_1=\left(\frac{q_s}{q_{s,b}}\right)^3\f$ where \f$q_s\f$ and \f$q_{s,b}\f$ are the saturation specific humidities at a given level and cloud base, respectively. The detrainment rate in the cloud is assumed to be equal to the entrainment rate at cloud base.
!     do i=1,im
!       if(cnvflg(i)) then
!         xlamx(i) = xlamue(i,kbcon(i))
!       endif
!     enddo
!     do k = 2, km1
!       do i=1,im
!         if(cnvflg(i).and.
!    &      (k > kbcon(i) .and. k < kmax(i))) then
!             xlamue(i,k) = xlamx(i)
!         endif
!       enddo
!     enddo
c
c  specify detrainment rate for the updrafts
c
!! (The updraft detrainment rate is set constant and equal to the entrainment rate at cloud base.)
!!
!> - The updraft detrainment rate is vertically constant and proportional to clamt
      do k = 1, km1
        do i=1,im
          if(cnvflg(i) .and. k < kmax(i)) then
!           xlamud(i,k) = xlamx(i)
!           xlamud(i,k) = crtlamd
            xlamud(i,k) = 0.001 * clamt(i)
          endif
        enddo
      enddo
c
c  entrainment functions decreasing with height (fent), 
c    mimicking a cloud ensemble
c    (Bechtold et al., 2008)
c
      do k = 2, km1
        do i=1,im
          if(cnvflg(i).and.
     &      (k > kbcon(i) .and. k < kmax(i))) then
              tem = qeso(i,k)/qeso(i,kbcon(i))
              fent1(i,k) = tem**2
              fent2(i,k) = tem**3
          endif
        enddo
      enddo
c
c  final entrainment and detrainment rates as the sum of turbulent part and
c    organized one depending on the environmental relative humidity
c    (Bechtold et al., 2008; Derbyshire et al., 2011)
c
      ! kgao 12/21/2023
      if (use_tke_conv) then
      ! new code
      do k = 2, km1
        do i=1,im
          if(cnvflg(i) .and.
     &      (k > kbcon(i) .and. k < kmax(i))) then
               tem = cxlamet(i) * frh(i,k) * fent2(i,k)
               xlamue(i,k) = xlamue(i,k)*fent1(i,k) + tem
               tem1 = cxlamdt(i) * frh(i,k)
               xlamud(i,k) = xlamud(i,k) + tem1
          endif
        enddo
      enddo

      else
      ! ori code
      do k = 2, km1
        do i=1,im
          if(cnvflg(i) .and.
     &      (k > kbcon(i) .and. k < kmax(i))) then
              tem = cxlame * frh(i,k) * fent2(i,k)
              xlamue(i,k) = xlamue(i,k)*fent1(i,k) + tem
              tem1 = cxlamd * frh(i,k)
              xlamud(i,k) = xlamud(i,k) + tem1
          endif
        enddo
      enddo

      endif ! end of use_tke_conv
!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
c
c  determine updraft mass flux for the subcloud layers
c
!> - Calculate the normalized mass flux for subcloud and in-cloud layers according to Pan and Wu (1995) \cite pan_and_wu_1995 equation 1:
!!  \f[
!!  \frac{1}{\eta}\frac{\partial \eta}{\partial z} = \lambda_e - \lambda_d
!!  \f]
!!  where \f$\eta\f$ is the normalized mass flux, \f$\lambda_e\f$ is the entrainment rate and \f$\lambda_d\f$ is the detrainment rate.
      do k = km1, 1, -1
        do i = 1, im
          if (cnvflg(i)) then
            if(k < kbcon(i) .and. k >= kb(i)) then
              dz       = zi(i,k+1) - zi(i,k)
              tem      = 0.5*(xlamud(i,k)+xlamud(i,k+1))
              ptem     = 0.5*(xlamue(i,k)+xlamue(i,k+1))-tem
              eta(i,k) = eta(i,k+1) / (1. + ptem * dz)
            endif
          endif
        enddo
      enddo
c
c  compute mass flux above cloud base
c
      do i = 1, im
        flg(i) = cnvflg(i)
      enddo
      do k = 2, km1
        do i = 1, im
         if(flg(i))then
           if(k > kbcon(i) .and. k < kmax(i)) then
              dz       = zi(i,k) - zi(i,k-1)
              tem      = 0.5*(xlamud(i,k)+xlamud(i,k-1))
              ptem     = 0.5*(xlamue(i,k)+xlamue(i,k-1))-tem
              eta(i,k) = eta(i,k-1) * (1 + ptem * dz)
              if(eta(i,k) <= 0.) then
                kmax(i) = k
                ktconn(i) = k
                flg(i)   = .false.
              endif
           endif
         endif
        enddo
      enddo
c
c  compute updraft cloud properties
c
!> - Set cloud properties equal to the state variables at updraft starting level (kb).
      do i = 1, im
        if(cnvflg(i)) then
          indx         = kb(i)
          hcko(i,indx) = heo(i,indx)
          ucko(i,indx) = uo(i,indx)
          vcko(i,indx) = vo(i,indx)
          pwavo(i)     = 0.
        endif
      enddo
!  for tracers
      do n = 1, ntr
        do i = 1, im
          if(cnvflg(i)) then
            indx = kb(i)
            ecko(i,indx,n) = ctro(i,indx,n)
          endif
        enddo
      enddo
c
c  cloud property is modified by the entrainment process
c
!  cm is an enhancement factor in entrainment rates for momentum
!
!> - Calculate the cloud properties as a parcel ascends, modified by entrainment and detrainment. Discretization follows Appendix B of Grell (1993) \cite grell_1993 . Following Han and Pan (2006) \cite han_and_pan_2006, the convective momentum transport is reduced by the convection-induced pressure gradient force by the constant "pgcon", currently set to 0.55 after Zhang and Wu (2003) \cite zhang_and_wu_2003 .
      do k = 2, km1
        do i = 1, im
          if (cnvflg(i)) then
            if(k > kb(i) .and. k < kmax(i)) then
              dz   = zi(i,k) - zi(i,k-1)
              tem  = 0.5 * (xlamue(i,k)+xlamue(i,k-1)) * dz
              tem1 = 0.25 * (xlamud(i,k)+xlamud(i,k-1)) * dz
              factor = 1. + tem - tem1
              hcko(i,k) = ((1.-tem1)*hcko(i,k-1)+tem*0.5*
     &                     (heo(i,k)+heo(i,k-1)))/factor
              dbyo(i,k) = hcko(i,k) - heso(i,k)
!
              tem  = 0.5 * cm * tem
              factor = 1. + tem
              ptem = tem + pgcon
              ptem1= tem - pgcon
              ucko(i,k) = ((1.-tem)*ucko(i,k-1)+ptem*uo(i,k)
     &                     +ptem1*uo(i,k-1))/factor
              vcko(i,k) = ((1.-tem)*vcko(i,k-1)+ptem*vo(i,k)
     &                     +ptem1*vo(i,k-1))/factor
            endif
          endif
        enddo
      enddo
      do n = 1, ntr
      do k = 2, km1
        do i = 1, im
          if (cnvflg(i)) then
            if(k > kb(i) .and. k < kmax(i)) then
              dz   = zi(i,k) - zi(i,k-1)
              tem  = 0.25 * (xlamue(i,k)+xlamue(i,k-1)) * dz
              factor = 1. + tem
              ecko(i,k,n) = ((1.-tem)*ecko(i,k-1,n)+tem*
     &                     (ctro(i,k,n)+ctro(i,k-1,n)))/factor
            endif
          endif
        enddo
      enddo
      enddo
c
c   taking account into convection inhibition due to existence of
c    dry layers below cloud base
c
!> - With entrainment, recalculate the LFC as the first level where buoyancy is positive. The difference in pressure levels between LFCs calculated with/without entrainment must be less than a threshold (currently 25 hPa). Otherwise, convection is inhibited and the scheme returns to the calling routine without modifying the state variables. This is the subcloud dryness trigger modification discussed in Han and Pan (2011) \cite han_and_pan_2011.
      do i=1,im
        flg(i) = cnvflg(i)
        kbcon1(i) = kmax(i)
      enddo
      do k = 2, km1
      do i=1,im
        if (flg(i) .and. k < kmax(i)) then
          if(k >= kbcon(i) .and. dbyo(i,k) > 0.) then
            kbcon1(i) = k
            flg(i)    = .false.
          endif
        endif
      enddo
      enddo
      do i=1,im
        if(cnvflg(i)) then
          if(kbcon1(i) == kmax(i)) cnvflg(i) = .false.
        endif
      enddo
      do i=1,im
        if(cnvflg(i)) then
          tem = pfld(i,kbcon(i)) - pfld(i,kbcon1(i))
          if(tem > dthk) then
             cnvflg(i) = .false.
          endif
        endif
      enddo
!!
      totflg = .true.
      do i = 1, im
        totflg = totflg .and. (.not. cnvflg(i))
      enddo
      if(totflg) return
!!
c
c  calculate convective inhibition
c
!> - Calculate additional trigger condition of the convective inhibition (CIN) according to Han et al.'s (2017) \cite han_et_al_2017 equation 13.
      do k = 2, km1
        do i = 1, im
          if (cnvflg(i)) then
            if(k > kb(i) .and. k < kbcon1(i)) then
              dz1 = zo(i,k+1) - zo(i,k)
              gamma = el2orc * qeso(i,k) / (to(i,k)**2)
              rfact =  1. + delta * cp * gamma
     &                 * to(i,k) / hvap
              cina(i) = cina(i) +
!    &                 dz1 * eta(i,k) * (g / (cp * to(i,k)))
     &                 dz1 * (g / (cp * to(i,k)))
     &                 * dbyo(i,k) / (1. + gamma)
     &                 * rfact
              val = 0.
              cina(i) = cina(i) +
!    &                 dz1 * eta(i,k) * g * delta *
     &                 dz1 * g * delta *
     &                 max(val,(qeso(i,k) - qo(i,k)))
            endif
          endif
        enddo
      enddo
!> - Turn off convection if the CIN is less than a critical value (cinacr) which is inversely proportional to the large-scale vertical velocity.
      do i = 1, im
        if(cnvflg(i)) then
!
          if(islimsk(i) == 1) then
            w1 = w1l
            w2 = w2l
            w3 = w3l
            w4 = w4l
          else
            w1 = w1s
            w2 = w2s
            w3 = w3s
            w4 = w4s
          endif
          if(pdot(i) <= w4) then
            tem = (pdot(i) - w4) / (w3 - w4)
          elseif(pdot(i) >= -w4) then
            tem = - (pdot(i) + w4) / (w4 - w3)
          else
            tem = 0.
          endif
 
          val1    =            -1.
          tem = max(tem,val1)
          val2    =             1.
          tem = min(tem,val2)
          tem = 1. - tem
          tem1= .5*(cinacrmx-cinacrmn)
          cinacr = cinacrmx - tem * tem1
!
!         cinacr = cinacrmx
          if(cina(i) < cinacr) cnvflg(i) = .false.
        endif
      enddo
!!
      totflg = .true.
      do i=1,im
        totflg = totflg .and. (.not. cnvflg(i))
      enddo
      if(totflg) return
!!
c
c  determine first guess cloud top as the level of zero buoyancy
c
!> - Calculate the cloud top as the first level where parcel buoyancy becomes negative. If the thickness of the calculated convection is less than a threshold (currently 200 hPa), then convection is inhibited, and the scheme returns to the calling routine.
      do i = 1, im
        flg(i) = cnvflg(i)
        ktcon(i) = 1
      enddo
      do k = 2, km1
      do i = 1, im
        if (flg(i) .and. k < kmax(i)) then
          if(k > kbcon1(i) .and. dbyo(i,k) < 0.) then
             ktcon(i) = k
             flg(i)   = .false.
          endif
        endif
      enddo
      enddo
c
      do i = 1, im
        if(cnvflg(i)) then
          if(ktcon(i) == 1 .and. ktconn(i) > 1) then
             ktcon(i) = ktconn(i)
          endif
          tem = pfld(i,kbcon(i))-pfld(i,ktcon(i))
          if(tem < cthk) cnvflg(i) = .false.
        endif
      enddo
!!
      totflg = .true.
      do i = 1, im
        totflg = totflg .and. (.not. cnvflg(i))
      enddo
      if(totflg) return
!!
c
c  search for downdraft originating level above theta-e minimum
c
!> - To originate the downdraft, search for the level above the minimum in moist static energy. Return to the calling routine without modification if this level is determined to be outside of the convective cloud layers.
      do i = 1, im
        if(cnvflg(i)) then
           hmin(i) = heo(i,kbcon1(i))
           lmin(i) = kbmax(i)
           jmin(i) = kbmax(i)
        endif
      enddo
      do k = 2, km1
        do i = 1, im
          if (cnvflg(i) .and. k <= kbmax(i)) then
            if(k > kbcon1(i) .and. heo(i,k) < hmin(i)) then
               lmin(i) = k + 1
               hmin(i) = heo(i,k)
            endif
          endif
        enddo
      enddo
c
c  make sure that jmin is within the cloud
c
      do i = 1, im
        if(cnvflg(i)) then
          jmin(i) = min(lmin(i),ktcon(i)-1)
          jmin(i) = max(jmin(i),kbcon1(i)+1)
          if(jmin(i) >= ktcon(i)) cnvflg(i) = .false.
        endif
      enddo
c
c  specify upper limit of mass flux at cloud base
c
!> - Calculate the maximum value of the cloud base mass flux using the CFL-criterion-based formula of Han and Pan (2011) \cite han_and_pan_2011, equation 7.
      do i = 1, im
        if(cnvflg(i)) then
!         xmbmax(i) = .1
!
          k = kbcon(i)
          dp = 1000. * del(i,k)
          xmbmax(i) = dp / (2. * g * dt2)
!
!         xmbmax(i) = dp / (g * dt2)
!
!         mbdt(i) = 0.1 * dp / g
!
!         tem = dp / (g * dt2)
!         xmbmax(i) = min(tem, xmbmax(i))
        endif
      enddo
c
c  compute cloud moisture property and precipitation
c
!> - Set cloud moisture property equal to the enviromental moisture at updraft starting level (kb).
      do i = 1, im
        if (cnvflg(i)) then
!         aa1(i) = 0.
          qcko(i,kb(i)) = qo(i,kb(i))
          qrcko(i,kb(i)) = qo(i,kb(i))
!         rhbar(i) = 0.
        endif
      enddo
!> - Calculate the moisture content of the entraining/detraining parcel (qcko) and the value it would have if just saturated (qrch), according to equation A.14 in Grell (1993) \cite grell_1993 . Their difference is the amount of convective cloud water (qlk = rain + condensate). Determine the portion of convective cloud water that remains suspended and the portion that is converted into convective precipitation (pwo). Calculate and save the negative cloud work function (aa1) due to water loading. The liquid water in the updraft layer is assumed to be detrained from the layers above the level of the minimum moist static energy into the grid-scale cloud water (dellal).
      do k = 2, km1
        do i = 1, im
          if (cnvflg(i)) then
            if(k > kb(i) .and. k < ktcon(i)) then
              dz    = zi(i,k) - zi(i,k-1)
              gamma = el2orc * qeso(i,k) / (to(i,k)**2)
              qrch = qeso(i,k)
     &             + gamma * dbyo(i,k) / (hvap * (1. + gamma))
cj
              tem  = 0.5 * (xlamue(i,k)+xlamue(i,k-1)) * dz
              tem1 = 0.25 * (xlamud(i,k)+xlamud(i,k-1)) * dz
              factor = 1. + tem - tem1
              qcko(i,k) = ((1.-tem1)*qcko(i,k-1)+tem*0.5*
     &                     (qo(i,k)+qo(i,k-1)))/factor
              qrcko(i,k) = qcko(i,k)
cj
              dq = eta(i,k) * (qcko(i,k) - qrch)
c
!             rhbar(i) = rhbar(i) + qo(i,k) / qeso(i,k)
c
c  check if there is excess moisture to release latent heat
c
              if(k >= kbcon(i) .and. dq > 0.) then
                etah = .5 * (eta(i,k) + eta(i,k-1))
                dp = 1000. * del(i,k)
                if(ncloud > 0 .and. k > jmin(i)) then
                  ptem = c0t(i,k) + c1
                  qlk = dq / (eta(i,k) + etah * ptem * dz)
                  dellal(i,k) = etah * c1 * dz * qlk * g / dp
                else
                  qlk = dq / (eta(i,k) + etah * c0t(i,k) * dz)
                endif
!               aa1(i) = aa1(i) - dz * g * qlk * etah
!               aa1(i) = aa1(i) - dz * g * qlk
                buo(i,k) = buo(i,k) - g * qlk
                qcko(i,k) = qlk + qrch
                pwo(i,k) = etah * c0t(i,k) * dz * qlk
                pwavo(i) = pwavo(i) + pwo(i,k)
!               cnvwt(i,k) = (etah*qlk + pwo(i,k)) * g / dp
                cnvwt(i,k) = etah * qlk * g / dp
              endif
!
!  compute buoyancy and drag for updraft velocity
!
              if(k >= kbcon(i)) then
                rfact =  1. + delta * cp * gamma
     &                   * to(i,k) / hvap
                buo(i,k) = buo(i,k) + (g / (cp * to(i,k)))
     &                   * dbyo(i,k) / (1. + gamma)
     &                   * rfact
                val = 0.
                buo(i,k) = buo(i,k) + g * delta *
     &                     max(val,(qeso(i,k) - qo(i,k)))
                drag(i,k) = max(xlamue(i,k),xlamud(i,k))

                ! kgao 12/18/2023: considers shear effect
                tem = ((uo(i,k)-uo(i,k-1))/dz)**2
                tem = tem+((vo(i,k)-vo(i,k-1))/dz)**2
                wush(i,k) = csmf * sqrt(tem)

              endif
!
            endif
          endif
        enddo
      enddo
c
!     do i = 1, im
!       if(cnvflg(i)) then
!         indx = ktcon(i) - kb(i) - 1
!         rhbar(i) = rhbar(i) / float(indx)
!       endif
!     enddo
c
c  calculate cloud work function
c
!     do k = 2, km1
!       do i = 1, im
!         if (cnvflg(i)) then
!           if(k >= kbcon(i) .and. k < ktcon(i)) then
!             dz1 = zo(i,k+1) - zo(i,k)
!             gamma = el2orc * qeso(i,k) / (to(i,k)**2)
!             rfact =  1. + delta * cp * gamma
!    &                 * to(i,k) / hvap
!             aa1(i) = aa1(i) +
!!   &                 dz1 * eta(i,k) * (g / (cp * to(i,k)))
!    &                 dz1 * (g / (cp * to(i,k)))
!    &                 * dbyo(i,k) / (1. + gamma)
!    &                 * rfact
!             val = 0.
!             aa1(i) = aa1(i) +
!!   &                 dz1 * eta(i,k) * g * delta *
!    &                 dz1 * g * delta *
!    &                 max(val,(qeso(i,k) - qo(i,k)))
!           endif
!         endif
!       enddo
!     enddo
!
!  calculate cloud work function
!
!> - Calculate the cloud work function according to Pan and Wu (1995) \cite pan_and_wu_1995 equation 4:
!!  \f[
!!  A_u=\int_{z_0}^{z_t}\frac{g}{c_pT(z)}\frac{\eta}{1 + \gamma}[h(z)-h^*(z)]dz
!!  \f]
!! (discretized according to Grell (1993) \cite grell_1993 equation B.10 using B.2 and B.3 of Arakawa and Schubert (1974) \cite arakawa_and_schubert_1974 and assuming \f$\eta=1\f$) where \f$A_u\f$ is the updraft cloud work function, \f$z_0\f$ and \f$z_t\f$ are cloud base and cloud top, respectively, \f$\gamma = \frac{L}{c_p}\left(\frac{\partial \overline{q_s}}{\partial T}\right)_p\f$ and other quantities are previously defined.
      do i = 1, im
        if (cnvflg(i)) then
          aa1(i) = 0.
        endif
      enddo
      do k = 2, km1
        do i = 1, im
          if (cnvflg(i)) then
            if(k >= kbcon(i) .and. k < ktcon(i)) then
              dz1 = zo(i,k+1) - zo(i,k)
!             aa1(i) = aa1(i) + buo(i,k) * dz1 * eta(i,k)
              aa1(i) = aa1(i) + buo(i,k) * dz1
            endif
          endif
        enddo
      enddo
!
!> - If the updraft cloud work function is negative, convection does not occur, and the scheme returns to the calling routine.
      do i = 1, im
        if(cnvflg(i) .and. aa1(i) <= 0.) cnvflg(i) = .false.
      enddo
!!
      totflg = .true.
      do i=1,im
        totflg = totflg .and. (.not. cnvflg(i))
      enddo
      if(totflg) return
!!
c
c  estimate the onvective overshooting as the level 
c    where the [aafac * cloud work function] becomes zero,
c    which is the final cloud top
c
!> - Continue calculating the cloud work function past the point of neutral buoyancy to represent overshooting according to Han and Pan (2011) \cite han_and_pan_2011 . Convective overshooting stops when \f$ cA_u < 0\f$ where \f$c\f$ is currently 10%, or when 10% of the updraft cloud work function has been consumed by the stable buoyancy force.
      do i = 1, im
        if (cnvflg(i)) then
          aa2(i) = aafac * aa1(i)
        endif
      enddo
c
      do i = 1, im
        flg(i) = cnvflg(i)
        ktcon1(i) = kmax(i)
      enddo
      do k = 2, km1
        do i = 1, im
          if (flg(i)) then
            if(k >= ktcon(i) .and. k < kmax(i)) then
              dz1 = zo(i,k+1) - zo(i,k)
              gamma = el2orc * qeso(i,k) / (to(i,k)**2)
              rfact =  1. + delta * cp * gamma
     &                 * to(i,k) / hvap
              aa2(i) = aa2(i) +
!    &                 dz1 * eta(i,k) * (g / (cp * to(i,k)))
     &                 dz1 * (g / (cp * to(i,k)))
     &                 * dbyo(i,k) / (1. + gamma)
     &                 * rfact
!             val = 0.
!             aa2(i) = aa2(i) +
!!   &                 dz1 * eta(i,k) * g * delta *
!    &                 dz1 * g * delta *
!    &                 max(val,(qeso(i,k) - qo(i,k)))
              if(aa2(i) < 0.) then
                ktcon1(i) = k
                flg(i) = .false.
              endif
            endif
          endif
        enddo
      enddo
c
c  compute cloud moisture property, detraining cloud water 
c    and precipitation in overshooting layers 
c
!> - For the overshooting convection, calculate the moisture content of the entraining/detraining parcel as before. Partition convective cloud water and precipitation and detrain convective cloud water above the mimimum in moist static energy.
      do k = 2, km1
        do i = 1, im
          if (cnvflg(i)) then
            if(k >= ktcon(i) .and. k < ktcon1(i)) then
              dz    = zi(i,k) - zi(i,k-1)
              gamma = el2orc * qeso(i,k) / (to(i,k)**2)
              qrch = qeso(i,k)
     &             + gamma * dbyo(i,k) / (hvap * (1. + gamma))
cj
              tem  = 0.5 * (xlamue(i,k)+xlamue(i,k-1)) * dz
              tem1 = 0.25 * (xlamud(i,k)+xlamud(i,k-1)) * dz
              factor = 1. + tem - tem1
              qcko(i,k) = ((1.-tem1)*qcko(i,k-1)+tem*0.5*
     &                     (qo(i,k)+qo(i,k-1)))/factor
              qrcko(i,k) = qcko(i,k)
cj
              dq = eta(i,k) * (qcko(i,k) - qrch)
c
c  check if there is excess moisture to release latent heat
c
              if(dq > 0.) then
                etah = .5 * (eta(i,k) + eta(i,k-1))
                dp = 1000. * del(i,k)
                if(ncloud > 0) then
                  ptem = c0t(i,k) + c1
                  qlk = dq / (eta(i,k) + etah * ptem * dz)
                  dellal(i,k) = etah * c1 * dz * qlk * g / dp
                else
                  qlk = dq / (eta(i,k) + etah * c0t(i,k) * dz)
                endif
                qcko(i,k) = qlk + qrch
                pwo(i,k) = etah * c0t(i,k) * dz * qlk
                pwavo(i) = pwavo(i) + pwo(i,k)
!               cnvwt(i,k) = (etah*qlk + pwo(i,k)) * g / dp
                cnvwt(i,k) = etah * qlk * g / dp
              endif
            endif
          endif
        enddo
      enddo
!
!  compute updraft velocity square(wu2)
!> - Calculate updraft velocity square(wu2) according to Han et al.'s (2017) \cite han_et_al_2017 equation 7.
!
!     bb1 = 2. * (1.+bet1*cd1)
!     bb2 = 2. / (f1*(1.+gam1))
!
!     bb1 = 3.9
!     bb2 = 0.67
!
!     bb1 = 2.0
!     bb2 = 4.0
!
!      bb1 = 4.0
!      bb2 = 0.8
!
!     do i = 1, im
!       if (cnvflg(i)) then
!         k = kbcon1(i)
!         tem = po(i,k) / (rd * to(i,k))
!         wucb = -0.01 * dot(i,k) / (tem * g)
!         if(wucb > 0.) then
!           wu2(i,k) = wucb * wucb
!         else
!           wu2(i,k) = 0.
!         endif
!       endif
!     enddo
      do k = 2, km1
        do i = 1, im
          if (cnvflg(i)) then
            if(k > kbcon1(i) .and. k < ktcon(i)) then
              dz    = zi(i,k) - zi(i,k-1)
              tem  = 0.25 * bb1 * (drag(i,k)+drag(i,k-1)) * dz
              tem1 = 0.5 * bb2 * (buo(i,k)+buo(i,k-1)) * dz
              ! kgao 12/18/2023
              if (use_shear_conv) then
                tem2 = wush(i,k) * sqrt(wu2(i,k-1))
                tem2 = (tem1 - tem2) * dz
                ptem = (1. - tem) * wu2(i,k-1)
                ptem1 = 1. + tem
                wu2(i,k) = (ptem + tem2) / ptem1
              else
                ptem = (1. - tem) * wu2(i,k-1)
                ptem1 = 1. + tem
                wu2(i,k) = (ptem + tem1) / ptem1
              endif
              wu2(i,k) = max(wu2(i,k), 0.)
            endif
          endif
        enddo
      enddo
!
!  compute updraft velocity average over the whole cumulus
!
!> - Calculate the mean updraft velocity within the cloud (wc).
      do i = 1, im
        wc(i) = 0.
        sumx(i) = 0.
      enddo
      do k = 2, km1
        do i = 1, im
          if (cnvflg(i)) then
            if(k > kbcon1(i) .and. k < ktcon(i)) then
              dz = zi(i,k) - zi(i,k-1)
              tem = 0.5 * (sqrt(wu2(i,k)) + sqrt(wu2(i,k-1)))
              wc(i) = wc(i) + tem * dz
              sumx(i) = sumx(i) + dz
            endif
          endif
        enddo
      enddo
      do i = 1, im
        if(cnvflg(i)) then
          if(sumx(i) == 0.) then
             cnvflg(i)=.false.
          else
             wc(i) = wc(i) / sumx(i)
          endif
          val = 1.e-4
          if (wc(i) < val) cnvflg(i)=.false.
        endif
      enddo
c
c exchange ktcon with ktcon1
c
!> - Swap the indices of the convective cloud top (ktcon) and the overshooting convection top (ktcon1) to use the same cloud top level in the calculations of \f$A^+\f$ and \f$A^*\f$.
      do i = 1, im
        if(cnvflg(i)) then
          kk = ktcon(i)
          ktcon(i) = ktcon1(i)
          ktcon1(i) = kk
        endif
      enddo
c
c  this section is ready for cloud water
c
!> - Separate the total updraft cloud water at cloud top into vapor and condensate.
      if(ncloud > 0) then
c
c  compute liquid and vapor separation at cloud top
c
      do i = 1, im
        if(cnvflg(i)) then
          k = ktcon(i) - 1
          gamma = el2orc * qeso(i,k) / (to(i,k)**2)
          qrch = qeso(i,k)
     &         + gamma * dbyo(i,k) / (hvap * (1. + gamma))
          dq = qcko(i,k) - qrch
c
c  check if there is excess moisture to release latent heat
c
          if(dq > 0.) then
            qlko_ktcon(i) = dq
            qcko(i,k) = qrch
          endif
        endif
      enddo
      endif
c
ccccc if(lat.==.latd.and.lon.==.lond.and.cnvflg(i)) then
ccccc   print *, ' aa1(i) before dwndrft =', aa1(i)
ccccc endif
c
c------- downdraft calculations
c
c--- compute precipitation efficiency in terms of windshear
c
!> ## Perform calculations related to the downdraft of the entraining/detraining cloud model ("static control").
!! - First, in order to calculate the downdraft mass flux (as a fraction of the updraft mass flux), calculate the wind shear and precipitation efficiency according to equation 58 in Fritsch and Chappell (1980) \cite fritsch_and_chappell_1980 :
!! \f[
!! E = 1.591 - 0.639\frac{\Delta V}{\Delta z} + 0.0953\left(\frac{\Delta V}{\Delta z}\right)^2 - 0.00496\left(\frac{\Delta V}{\Delta z}\right)^3
!! \f]
!! where \f$\Delta V\f$ is the integrated horizontal shear over the cloud depth, \f$\Delta z\f$, (the ratio is converted to units of \f$10^{-3} s^{-1}\f$). The variable "edto" is \f$1-E\f$ and is constrained to the range \f$[0,0.9]\f$.
      do i = 1, im
        if(cnvflg(i)) then
          vshear(i) = 0.
        endif
      enddo
      do k = 2, km
        do i = 1, im
          if (cnvflg(i)) then
            if(k > kb(i) .and. k <= ktcon(i)) then
              shear= sqrt((uo(i,k)-uo(i,k-1)) ** 2
     &                  + (vo(i,k)-vo(i,k-1)) ** 2)
              vshear(i) = vshear(i) + shear
            endif
          endif
        enddo
      enddo
      do i = 1, im
        if(cnvflg(i)) then
          vshear(i) = 1.e3 * vshear(i) / (zi(i,ktcon(i))-zi(i,kb(i)))
          e1=1.591-.639*vshear(i)
     &       +.0953*(vshear(i)**2)-.00496*(vshear(i)**3)
          edt(i)=1.-e1
          val =         .9
          edt(i) = min(edt(i),val)
          val =         .0
          edt(i) = max(edt(i),val)
          edto(i)=edt(i)
          edtx(i)=edt(i)
        endif
      enddo
c
c  determine detrainment rate between 1 and kbcon
c
!> - Next, calculate the variable detrainment rate between the surface and the LFC according to:
!! \f[
!! \lambda_d = \frac{1-\beta^{\frac{1}{k_{LFC}}}}{\overline{\Delta z}}
!! \f]
!! \f$\lambda_d\f$ is the detrainment rate, \f$\beta\f$ is a constant currently set to 0.05, implying that only 5% of downdraft mass flux at LFC reaches the ground surface due to detrainment, \f$k_{LFC}\f$ is the vertical index of the LFC level, and \f$\overline{\Delta z}\f$ is the average vertical grid spacing below the LFC.
      do i = 1, im
        if(cnvflg(i)) then
          sumx(i) = 0.
        endif
      enddo
      do k = 1, km1
      do i = 1, im
        if(cnvflg(i)) then
          if(k >= 1 .and. k < kbcon(i)) then
            dz = zi(i,k+1) - zi(i,k)
            sumx(i) = sumx(i) + dz
          endif
        endif
      enddo
      enddo
      do i = 1, im
        if(cnvflg(i)) then
          betamn = betas
          if(islimsk(i) == 1) betamn = betal
          if(ntk > 0) then
            betamx = betamn + dbeta
            if(tkemean(i) > tkemx) then
              beta = betamn
            else if(tkemean(i) < tkemn) then
              beta = betamx
            else
              tem = (betamx - betamn) * (tkemean(i) - tkemn)
              beta = betamx - tem  / dtke
            endif
          else
            beta = betamn
          endif
          dz  = (sumx(i)+zi(i,1))/float(kbcon(i))
          tem = 1./float(kbcon(i))
          xlamd(i) = (1.-beta**tem)/dz
        endif
      enddo
c
c  determine downdraft mass flux
c
!> - Calculate the normalized downdraft mass flux from equation 1 of Pan and Wu (1995) \cite pan_and_wu_1995 . Downdraft entrainment and detrainment rates are constants from the downdraft origination to the LFC.
      do k = km1, 1, -1
        do i = 1, im
          if (cnvflg(i) .and. k <= kmax(i)-1) then
           if(k < jmin(i) .and. k >= kbcon(i)) then
              dz        = zi(i,k+1) - zi(i,k)
              ! kgao 12/18/2023
              if (use_tke_conv) then
                ptem      = xlamddt(i) - xlamdet(i)
              else
                ptem      = xlamdd - xlamde
              endif
              etad(i,k) = etad(i,k+1) * (1. - ptem * dz)
           else if(k < kbcon(i)) then
              dz        = zi(i,k+1) - zi(i,k)
              ! kgao 12/18/2023
              if (use_tke_conv) then
                ptem      = xlamd(i) + xlamddt(i) - xlamdet(i)
              else
                ptem      = xlamd(i) + xlamdd - xlamde
              endif
              etad(i,k) = etad(i,k+1) * (1. - ptem * dz)
           endif
          endif
        enddo
      enddo
c
c--- downdraft moisture properties
c
!> - Set initial cloud downdraft properties equal to the state variables at the downdraft origination level.
      do i = 1, im
        if(cnvflg(i)) then
          jmn = jmin(i)
          hcdo(i,jmn) = heo(i,jmn)
          qcdo(i,jmn) = qo(i,jmn)
          qrcdo(i,jmn)= qo(i,jmn)
          ucdo(i,jmn) = uo(i,jmn)
          vcdo(i,jmn) = vo(i,jmn)
          pwevo(i) = 0.
        endif
      enddo
! for tracers
      do n = 1, ntr
        do i = 1, im
          if(cnvflg(i)) then
            jmn = jmin(i)
            ecdo(i,jmn,n) = ctro(i,jmn,n)
          endif
        enddo
      enddo
cj
!> - Calculate the cloud properties as a parcel descends, modified by entrainment and detrainment. Discretization follows Appendix B of Grell (1993) \cite grell_1993 .
      do k = km1, 1, -1
        do i = 1, im
          if (cnvflg(i) .and. k < jmin(i)) then
              dz = zi(i,k+1) - zi(i,k)
              if(k >= kbcon(i)) then
                 ! kgao 12/18/2023
                 if (use_tke_conv) then
                   tem  = xlamdet(i) * dz
                   tem1 = 0.5 * xlamddt(i) * dz
                 else
                   tem  = xlamde * dz
                   tem1 = 0.5 * xlamdd * dz
                 endif
              else
                 ! kgao 12/18/2023
                 if (use_tke_conv) then
                   tem  = xlamdet(i) * dz
                   tem1 = 0.5 * (xlamd(i)+xlamddt(i)) * dz
                 else
                   tem  = xlamde * dz
                   tem1 = 0.5 * (xlamd(i)+xlamdd) * dz
                 endif
              endif
              factor = 1. + tem - tem1
              hcdo(i,k) = ((1.-tem1)*hcdo(i,k+1)+tem*0.5*
     &                     (heo(i,k)+heo(i,k+1)))/factor
              dbyo(i,k) = hcdo(i,k) - heso(i,k)
!
              tem  = 0.5 * cm * tem
              factor = 1. + tem
              ptem = tem - pgcon
              ptem1= tem + pgcon
              ucdo(i,k) = ((1.-tem)*ucdo(i,k+1)+ptem*uo(i,k+1)
     &                     +ptem1*uo(i,k))/factor
              vcdo(i,k) = ((1.-tem)*vcdo(i,k+1)+ptem*vo(i,k+1)
     &                     +ptem1*vo(i,k))/factor
          endif
        enddo
      enddo
      do n = 1, ntr
      do k = km1, 1, -1
        do i = 1, im
          if (cnvflg(i) .and. k < jmin(i)) then
              dz = zi(i,k+1) - zi(i,k)
              ! kgao 12/18/2023
              if (use_tke_conv) then
                tem  = 0.5 * xlamdet(i) * dz
              else
                tem  = 0.5 * xlamde * dz
              endif
              factor = 1. + tem
              ecdo(i,k,n) = ((1.-tem)*ecdo(i,k+1,n)+tem*
     &                     (ctro(i,k,n)+ctro(i,k+1,n)))/factor
          endif
        enddo
      enddo
      enddo
c
!> - Compute the amount of moisture that is necessary to keep the downdraft saturated.
      do k = km1, 1, -1
        do i = 1, im
          if (cnvflg(i) .and. k < jmin(i)) then
              gamma      = el2orc * qeso(i,k) / (to(i,k)**2)
              qrcdo(i,k) = qeso(i,k)+
     &                (1./hvap)*(gamma/(1.+gamma))*dbyo(i,k)
!             detad      = etad(i,k+1) - etad(i,k)
cj
              dz = zi(i,k+1) - zi(i,k)

              ! kgao 12/18/2023
              if (use_tke_conv) then
                if(k >= kbcon(i)) then
                   tem  = xlamdet(i) * dz
                   tem1 = 0.5 * xlamddt(i) * dz
                else
                   tem  = xlamdet(i) * dz
                   tem1 = 0.5 * (xlamd(i)+xlamddt(i)) * dz
                endif
              else
                if(k >= kbcon(i)) then
                   tem  = xlamde * dz
                   tem1 = 0.5 * xlamdd * dz
                else
                   tem  = xlamde * dz
                   tem1 = 0.5 * (xlamd(i)+xlamdd) * dz
                endif
              endif

              factor = 1. + tem - tem1
              qcdo(i,k) = ((1.-tem1)*qrcdo(i,k+1)+tem*0.5*
     &                     (qo(i,k)+qo(i,k+1)))/factor
cj
!             pwdo(i,k)  = etad(i,k+1) * qcdo(i,k+1) -
!    &                     etad(i,k) * qrcdo(i,k)
!             pwdo(i,k)  = pwdo(i,k) - detad *
!    &                    .5 * (qrcdo(i,k) + qrcdo(i,k+1))
cj
              pwdo(i,k)  = etad(i,k) * (qcdo(i,k) - qrcdo(i,k))
              pwevo(i)   = pwevo(i) + pwdo(i,k)
          endif
        enddo
      enddo
c
c--- final downdraft strength dependent on precip
c--- efficiency (edt), normalized condensate (pwav), and
c--- evaporate (pwev)
c
!> - Update the precipitation efficiency (edto) based on the ratio of normalized cloud condensate (pwavo) to normalized cloud evaporate (pwevo).
      do i = 1, im
        edtmax = edtmaxl
        if(islimsk(i) == 0) edtmax = edtmaxs
        if(cnvflg(i)) then
          if(pwevo(i) < 0.) then
            edto(i) = -edto(i) * pwavo(i) / pwevo(i)
            edto(i) = min(edto(i),edtmax)
          else
            edto(i) = 0.
          endif
        endif
      enddo
c
c--- downdraft cloudwork functions
c
!> - Calculate downdraft cloud work function (\f$A_d\f$) according to equation A.42 (discretized by B.11) in Grell (1993) \cite grell_1993 . Add it to the updraft cloud work function, \f$A_u\f$.
      do k = km1, 1, -1
        do i = 1, im
          if (cnvflg(i) .and. k < jmin(i)) then
              gamma = el2orc * qeso(i,k) / to(i,k)**2
              dhh=hcdo(i,k)
              dt=to(i,k)
              dg=gamma
              dh=heso(i,k)
              dz=-1.*(zo(i,k+1)-zo(i,k))
!             aa1(i)=aa1(i)+edto(i)*dz*etad(i,k)
              aa1(i)=aa1(i)+edto(i)*dz
     &               *(g/(cp*dt))*((dhh-dh)/(1.+dg))
     &               *(1.+delta*cp*dg*dt/hvap)
              val=0.
!             aa1(i)=aa1(i)+edto(i)*dz*etad(i,k)
              aa1(i)=aa1(i)+edto(i)*dz
     &               *g*delta*max(val,(qeso(i,k)-qo(i,k)))
          endif
        enddo
      enddo
!> - Check for negative total cloud work function; if found, return to calling routine without modifying state variables.
      do i = 1, im
        if(cnvflg(i) .and. aa1(i) <= 0.) then
           cnvflg(i) = .false.
        endif
      enddo
!!
      totflg = .true.
      do i=1,im
        totflg = totflg .and. (.not. cnvflg(i))
      enddo
      if(totflg) return
!!
c
c--- what would the change be, that a cloud with unit mass
c--- will do to the environment?
c
!> - Calculate the change in moist static energy, moisture mixing ratio, and horizontal winds per unit cloud base mass flux near the surface using equations B.18 and B.19 from Grell (1993) \cite grell_1993, for all layers below cloud top from equations B.14 and B.15, and for the cloud top from B.16 and B.17.
      do k = 1, km
        do i = 1, im
          if(cnvflg(i) .and. k <= kmax(i)) then
            dellah(i,k) = 0.
            dellaq(i,k) = 0.
            dellau(i,k) = 0.
            dellav(i,k) = 0.
          endif
        enddo
      enddo
      do n = 1, ntr
      do k = 1, km
        do i = 1, im
          if(cnvflg(i) .and. k <= kmax(i)) then
            dellae(i,k,n) = 0.
          endif
        enddo
      enddo
      enddo
      do i = 1, im
        if(cnvflg(i)) then
          dp = 1000. * del(i,1)
          dellah(i,1) = edto(i) * etad(i,1) * (hcdo(i,1)
     &                   - heo(i,1)) * g / dp
          dellaq(i,1) = edto(i) * etad(i,1) * (qrcdo(i,1)
     &                   - qo(i,1)) * g / dp
          dellau(i,1) = edto(i) * etad(i,1) * (ucdo(i,1)
     &                   - uo(i,1)) * g / dp
          dellav(i,1) = edto(i) * etad(i,1) * (vcdo(i,1)
     &                   - vo(i,1)) * g / dp
        endif
      enddo
      do n = 1, ntr
      do i = 1, im
        if(cnvflg(i)) then
          dp = 1000. * del(i,1)
          dellae(i,1,n) = edto(i) * etad(i,1) * (ecdo(i,1,n)
     &                   - ctro(i,1,n)) * g / dp
        endif
      enddo
      enddo
c
c--- changed due to subsidence and entrainment
c
      do k = 2, km1
        do i = 1, im
          if (cnvflg(i) .and. k < ktcon(i)) then
              aup = 1.
              if(k <= kb(i)) aup = 0.
              adw = 1.
              if(k > jmin(i)) adw = 0.
              dp = 1000. * del(i,k)
              dz = zi(i,k) - zi(i,k-1)
c
              dv1h = heo(i,k)
              dv2h = .5 * (heo(i,k) + heo(i,k-1))
              dv3h = heo(i,k-1)
              dv1q = qo(i,k)
              dv2q = .5 * (qo(i,k) + qo(i,k-1))
              dv3q = qo(i,k-1)
c
              tem  = 0.5 * (xlamue(i,k)+xlamue(i,k-1))
              tem1 = 0.5 * (xlamud(i,k)+xlamud(i,k-1))
ci
              ! kgao 12/18/2023
              if (use_tke_conv) then
                if(k <= kbcon(i)) then
                  ptem  = xlamdet(i)
                  ptem1 = xlamd(i)+xlamddt(i)
                else
                  ptem  = xlamdet(i)
                  ptem1 = xlamddt(i)
                endif
              else
                if(k <= kbcon(i)) then
                  ptem  = xlamde
                  ptem1 = xlamd(i)+xlamdd
                else
                  ptem  = xlamde
                  ptem1 = xlamdd
                endif
              endif
cj
              dellah(i,k) = dellah(i,k) +
     &     ((aup*eta(i,k)-adw*edto(i)*etad(i,k))*dv1h
     &    - (aup*eta(i,k-1)-adw*edto(i)*etad(i,k-1))*dv3h
     &    - (aup*tem*eta(i,k-1)+adw*edto(i)*ptem*etad(i,k))*dv2h*dz
     &    +  aup*tem1*eta(i,k-1)*.5*(hcko(i,k)+hcko(i,k-1))*dz
     &    +  adw*edto(i)*ptem1*etad(i,k)*.5*(hcdo(i,k)+hcdo(i,k-1))*dz
     &         ) *g/dp
cj
              dellaq(i,k) = dellaq(i,k) +
     &     ((aup*eta(i,k)-adw*edto(i)*etad(i,k))*dv1q
     &    - (aup*eta(i,k-1)-adw*edto(i)*etad(i,k-1))*dv3q
     &    - (aup*tem*eta(i,k-1)+adw*edto(i)*ptem*etad(i,k))*dv2q*dz
     &    +  aup*tem1*eta(i,k-1)*.5*(qrcko(i,k)+qcko(i,k-1))*dz
     &    +  adw*edto(i)*ptem1*etad(i,k)*.5*(qrcdo(i,k)+qcdo(i,k-1))*dz
     &         ) *g/dp
cj
              tem1=eta(i,k)*(uo(i,k)-ucko(i,k))
              tem2=eta(i,k-1)*(uo(i,k-1)-ucko(i,k-1))
              ptem1=etad(i,k)*(uo(i,k)-ucdo(i,k))
              ptem2=etad(i,k-1)*(uo(i,k-1)-ucdo(i,k-1))
              dellau(i,k) = dellau(i,k) + 
     &           (aup*(tem1-tem2)-adw*edto(i)*(ptem1-ptem2))*g/dp
cj
              tem1=eta(i,k)*(vo(i,k)-vcko(i,k))
              tem2=eta(i,k-1)*(vo(i,k-1)-vcko(i,k-1))
              ptem1=etad(i,k)*(vo(i,k)-vcdo(i,k))
              ptem2=etad(i,k-1)*(vo(i,k-1)-vcdo(i,k-1))
              dellav(i,k) = dellav(i,k) + 
     &           (aup*(tem1-tem2)-adw*edto(i)*(ptem1-ptem2))*g/dp
cj
          endif
        enddo
      enddo
      do n = 1, ntr
      do k = 2, km1
        do i = 1, im
          if (cnvflg(i) .and. k < ktcon(i)) then
              aup = 1.
              if(k <= kb(i)) aup = 0.
              adw = 1.
              if(k > jmin(i)) adw = 0.
              dp = 1000. * del(i,k)
cj
              tem1=eta(i,k)*(ctro(i,k,n)-ecko(i,k,n))
              tem2=eta(i,k-1)*(ctro(i,k-1,n)-ecko(i,k-1,n))
              ptem1=etad(i,k)*(ctro(i,k,n)-ecdo(i,k,n))
              ptem2=etad(i,k-1)*(ctro(i,k-1,n)-ecdo(i,k-1,n))
              dellae(i,k,n) = dellae(i,k,n) +
     &           (aup*(tem1-tem2)-adw*edto(i)*(ptem1-ptem2))*g/dp
cj
          endif
        enddo
      enddo
      enddo
c
c------- cloud top
c
      do i = 1, im
        if(cnvflg(i)) then
          indx = ktcon(i)
          dp = 1000. * del(i,indx)
          dv1h = heo(i,indx-1)
          dellah(i,indx) = eta(i,indx-1) *
     &                     (hcko(i,indx-1) - dv1h) * g / dp
          dv1q = qo(i,indx-1)
          dellaq(i,indx) = eta(i,indx-1) *
     &                     (qcko(i,indx-1) - dv1q) * g / dp
          dellau(i,indx) = eta(i,indx-1) *
     &             (ucko(i,indx-1) - uo(i,indx-1)) * g / dp
          dellav(i,indx) = eta(i,indx-1) *
     &             (vcko(i,indx-1) - vo(i,indx-1)) * g / dp
c
c  cloud water
c
          dellal(i,indx) = eta(i,indx-1) *
     &                     qlko_ktcon(i) * g / dp
        endif
      enddo
      do n = 1, ntr
      do i = 1, im
        if(cnvflg(i)) then
          indx = ktcon(i)
          dp = 1000. * del(i,indx)
          dellae(i,indx,n) = eta(i,indx-1) *
     &           (ecko(i,indx-1,n) - ctro(i,indx-1,n)) * g / dp
        endif
      enddo
      enddo
c
c------- final changed variable per unit mass flux
c
!> - If grid size is less than a threshold value (dxcrtas: currently 8km), the quasi-equilibrium assumption of Arakawa-Schubert is not used any longer.
!
      do i = 1, im
         asqecflg(i) = cnvflg(i)
         if(asqecflg(i) .and. gdx(i) < dxcrtas) then
            asqecflg(i) = .false.
         endif
      enddo
!
!> - If grid size is larger than the threshold value (i.e., asqecflg=.true.), the quasi-equilibrium assumption is used to obtain the cloud base mass flux. To begin with, calculate the change in the temperature and moisture profiles per unit cloud base mass flux.
      do k = 1, km
        do i = 1, im
          if (asqecflg(i) .and. k <= kmax(i)) then
            if(k > ktcon(i)) then
              qo(i,k) = q1(i,k)
              to(i,k) = t1(i,k)
            endif
            if(k <= ktcon(i)) then
              qo(i,k) = dellaq(i,k) * mbdt(i) + q1(i,k)
              dellat = (dellah(i,k) - hvap * dellaq(i,k)) / cp
              to(i,k) = dellat * mbdt(i) + t1(i,k)
              val   =           1.e-10
              qo(i,k) = max(qo(i,k), val  )
            endif
          endif
        enddo
      enddo
c!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
c
c--- the above changed environment is now used to calulate the
c--- effect the arbitrary cloud (with unit mass flux)
c--- would have on the stability,
c--- which then is used to calculate the real mass flux,
c--- necessary to keep this change in balance with the large-scale
c--- destabilization.
c
c--- environmental conditions again, first heights
c
!> ## Using the updated temperature and moisture profiles that were modified by the convection on a short time-scale, recalculate the total cloud work function to determine the change in the cloud work function due to convection, or the stabilizing effect of the cumulus.
!! - Using notation from Pan and Wu (1995) \cite pan_and_wu_1995, the previously calculated cloud work function is denoted by \f$A^+\f$. Now, it is necessary to use the entraining/detraining cloud model ("static control") to determine the cloud work function of the environment after the stabilization of the arbitrary convective element (per unit cloud base mass flux) has been applied, denoted by \f$A^*\f$.
!! - Recalculate saturation specific humidity.
      do k = 1, km
        do i = 1, im
          if(asqecflg(i) .and. k <= kmax(i)) then
            qeso(i,k) = 0.01 * fpvs(to(i,k))      ! fpvs is in pa
            qeso(i,k) = eps * qeso(i,k) / (pfld(i,k)+epsm1*qeso(i,k))
            val       =             1.e-8
            qeso(i,k) = max(qeso(i,k), val )
!           tvo(i,k)  = to(i,k) + delta * to(i,k) * qo(i,k)
          endif
        enddo
      enddo
c
c--- moist static energy
c
!! - Recalculate moist static energy and saturation moist static energy.
      do k = 1, km1
        do i = 1, im
          if(asqecflg(i) .and. k <= kmax(i)-1) then
            dz = .5 * (zo(i,k+1) - zo(i,k))
            dp = .5 * (pfld(i,k+1) - pfld(i,k))
            es = 0.01 * fpvs(to(i,k+1))      ! fpvs is in pa
            pprime = pfld(i,k+1) + epsm1 * es
            qs = eps * es / pprime
            dqsdp = - qs / pprime
            desdt = es * (fact1 / to(i,k+1) + fact2 / (to(i,k+1)**2))
            dqsdt = qs * pfld(i,k+1) * desdt / (es * pprime)
            gamma = el2orc * qeso(i,k+1) / (to(i,k+1)**2)
            dt = (g * dz + hvap * dqsdp * dp) / (cp * (1. + gamma))
            dq = dqsdt * dt + dqsdp * dp
            to(i,k) = to(i,k+1) + dt
            qo(i,k) = qo(i,k+1) + dq
            po(i,k) = .5 * (pfld(i,k) + pfld(i,k+1))
          endif
        enddo
      enddo
      do k = 1, km1
        do i = 1, im
          if(asqecflg(i) .and. k <= kmax(i)-1) then
            qeso(i,k) = 0.01 * fpvs(to(i,k))      ! fpvs is in pa
            qeso(i,k) = eps * qeso(i,k) / (po(i,k) + epsm1 * qeso(i,k))
            val1      =             1.e-8
            qeso(i,k) = max(qeso(i,k), val1)
            val2      =           1.e-10
            qo(i,k)   = max(qo(i,k), val2 )
!           qo(i,k)   = min(qo(i,k),qeso(i,k))
            heo(i,k)   = .5 * g * (zo(i,k) + zo(i,k+1)) +
     &                    cp * to(i,k) + hvap * qo(i,k)
            heso(i,k) = .5 * g * (zo(i,k) + zo(i,k+1)) +
     &                  cp * to(i,k) + hvap * qeso(i,k)
          endif
        enddo
      enddo
      do i = 1, im
        if(asqecflg(i)) then
          k = kmax(i)
          heo(i,k) = g * zo(i,k) + cp * to(i,k) + hvap * qo(i,k)
          heso(i,k) = g * zo(i,k) + cp * to(i,k) + hvap * qeso(i,k)
c         heo(i,k) = min(heo(i,k),heso(i,k))
        endif
      enddo
c
c**************************** static control
c
c------- moisture and cloud work functions
c
!> - As before, recalculate the updraft cloud work function.
      do i = 1, im
        if(asqecflg(i)) then
          xaa0(i) = 0.
          xpwav(i) = 0.
        endif
      enddo
c
      do i = 1, im
        if(asqecflg(i)) then
          indx = kb(i)
          hcko(i,indx) = heo(i,indx)
          qcko(i,indx) = qo(i,indx)
        endif
      enddo
      do k = 2, km1
        do i = 1, im
          if (asqecflg(i)) then
            if(k > kb(i) .and. k <= ktcon(i)) then
              dz = zi(i,k) - zi(i,k-1)
              tem  = 0.5 * (xlamue(i,k)+xlamue(i,k-1)) * dz
              tem1 = 0.25 * (xlamud(i,k)+xlamud(i,k-1)) * dz
              factor = 1. + tem - tem1
              hcko(i,k) = ((1.-tem1)*hcko(i,k-1)+tem*0.5*
     &                     (heo(i,k)+heo(i,k-1)))/factor
            endif
          endif
        enddo
      enddo
      do k = 2, km1
        do i = 1, im
          if (asqecflg(i)) then
            if(k > kb(i) .and. k < ktcon(i)) then
              dz = zi(i,k) - zi(i,k-1)
              gamma = el2orc * qeso(i,k) / (to(i,k)**2)
              xdby = hcko(i,k) - heso(i,k)
              xqrch = qeso(i,k)
     &              + gamma * xdby / (hvap * (1. + gamma))
cj
              tem  = 0.5 * (xlamue(i,k)+xlamue(i,k-1)) * dz
              tem1 = 0.25 * (xlamud(i,k)+xlamud(i,k-1)) * dz
              factor = 1. + tem - tem1
              qcko(i,k) = ((1.-tem1)*qcko(i,k-1)+tem*0.5*
     &                     (qo(i,k)+qo(i,k-1)))/factor
cj
              dq = eta(i,k) * (qcko(i,k) - xqrch)
c
              if(k >= kbcon(i) .and. dq > 0.) then
                etah = .5 * (eta(i,k) + eta(i,k-1))
                if(ncloud > 0 .and. k > jmin(i)) then
                  ptem = c0t(i,k) + c1
                  qlk = dq / (eta(i,k) + etah * ptem * dz)
                else
                  qlk = dq / (eta(i,k) + etah * c0t(i,k) * dz)
                endif
                if(k < ktcon1(i)) then
!                 xaa0(i) = xaa0(i) - dz * g * qlk * etah
                  xaa0(i) = xaa0(i) - dz * g * qlk
                endif
                qcko(i,k) = qlk + xqrch
                xpw = etah * c0t(i,k) * dz * qlk
                xpwav(i) = xpwav(i) + xpw
              endif
            endif
            if(k >= kbcon(i) .and. k < ktcon1(i)) then
              dz1 = zo(i,k+1) - zo(i,k)
              gamma = el2orc * qeso(i,k) / (to(i,k)**2)
              rfact =  1. + delta * cp * gamma
     &                 * to(i,k) / hvap
              xaa0(i) = xaa0(i)
!    &                + dz1 * eta(i,k) * (g / (cp * to(i,k)))
     &                + dz1 * (g / (cp * to(i,k)))
     &                * xdby / (1. + gamma)
     &                * rfact
              val=0.
              xaa0(i) = xaa0(i) +
!    &                 dz1 * eta(i,k) * g * delta *
     &                 dz1 * g * delta *
     &                 max(val,(qeso(i,k) - qo(i,k)))
            endif
          endif
        enddo
      enddo
c
c------- downdraft calculations
c
c--- downdraft moisture properties
c
!> - As before, recalculate the downdraft cloud work function.
      do i = 1, im
        if(asqecflg(i)) then
          jmn = jmin(i)
          hcdo(i,jmn) = heo(i,jmn)
          qcdo(i,jmn) = qo(i,jmn)
          qrcd(i,jmn) = qo(i,jmn)
          xpwev(i) = 0.
        endif
      enddo
cj
      do k = km1, 1, -1
        do i = 1, im
          if (asqecflg(i) .and. k < jmin(i)) then
              dz = zi(i,k+1) - zi(i,k)

              ! kgao 12/18/2023
              if (use_tke_conv) then
                if(k >= kbcon(i)) then
                   tem  = xlamdet(i) * dz
                   tem1 = 0.5 * xlamddt(i) * dz
                else
                   tem  = xlamdet(i) * dz
                   tem1 = 0.5 * (xlamd(i)+xlamddt(i)) * dz
                endif
              else  
                if(k >= kbcon(i)) then
                   tem  = xlamde * dz
                   tem1 = 0.5 * xlamdd * dz
                else
                   tem  = xlamde * dz
                   tem1 = 0.5 * (xlamd(i)+xlamdd) * dz
                endif
              endif
              factor = 1. + tem - tem1
              hcdo(i,k) = ((1.-tem1)*hcdo(i,k+1)+tem*0.5*
     &                     (heo(i,k)+heo(i,k+1)))/factor
          endif
        enddo
      enddo
cj
      do k = km1, 1, -1
        do i = 1, im
          if (asqecflg(i) .and. k < jmin(i)) then
              dq = qeso(i,k)
              dt = to(i,k)
              gamma    = el2orc * dq / dt**2
              dh       = hcdo(i,k) - heso(i,k)
              qrcd(i,k)=dq+(1./hvap)*(gamma/(1.+gamma))*dh
!             detad    = etad(i,k+1) - etad(i,k)
cj
              dz = zi(i,k+1) - zi(i,k)

              ! kgao 12/18/2023
              if (use_tke_conv) then
                if(k >= kbcon(i)) then
                   tem  = xlamdet(i) * dz
                   tem1 = 0.5 * xlamddt(i) * dz
                else
                   tem  = xlamdet(i) * dz
                   tem1 = 0.5 * (xlamd(i)+xlamddt(i)) * dz
                endif
              else
                if(k >= kbcon(i)) then
                   tem  = xlamde * dz
                   tem1 = 0.5 * xlamdd * dz
                else
                   tem  = xlamde * dz
                   tem1 = 0.5 * (xlamd(i)+xlamdd) * dz
                endif
              endif
              factor = 1. + tem - tem1
              qcdo(i,k) = ((1.-tem1)*qrcd(i,k+1)+tem*0.5*
     &                     (qo(i,k)+qo(i,k+1)))/factor
cj
!             xpwd     = etad(i,k+1) * qcdo(i,k+1) -
!    &                   etad(i,k) * qrcd(i,k)
!             xpwd     = xpwd - detad *
!    &                 .5 * (qrcd(i,k) + qrcd(i,k+1))
cj
              xpwd     = etad(i,k) * (qcdo(i,k) - qrcd(i,k))
              xpwev(i) = xpwev(i) + xpwd
          endif
        enddo
      enddo
c
      do i = 1, im
        edtmax = edtmaxl
        if(islimsk(i) == 0) edtmax = edtmaxs
        if(asqecflg(i)) then
          if(xpwev(i) >= 0.) then
            edtx(i) = 0.
          else
            edtx(i) = -edtx(i) * xpwav(i) / xpwev(i)
            edtx(i) = min(edtx(i),edtmax)
          endif
        endif
      enddo
c
c
c--- downdraft cloudwork functions
c
c
      do k = km1, 1, -1
        do i = 1, im
          if (asqecflg(i) .and. k < jmin(i)) then
              gamma = el2orc * qeso(i,k) / to(i,k)**2
              dhh=hcdo(i,k)
              dt= to(i,k)
              dg= gamma
              dh= heso(i,k)
              dz=-1.*(zo(i,k+1)-zo(i,k))
!             xaa0(i)=xaa0(i)+edtx(i)*dz*etad(i,k)
              xaa0(i)=xaa0(i)+edtx(i)*dz
     &                *(g/(cp*dt))*((dhh-dh)/(1.+dg))
     &                *(1.+delta*cp*dg*dt/hvap)
              val=0.
!             xaa0(i)=xaa0(i)+edtx(i)*dz*etad(i,k)
              xaa0(i)=xaa0(i)+edtx(i)*dz
     &                *g*delta*max(val,(qeso(i,k)-qo(i,k)))
          endif
        enddo
      enddo
c
c  calculate critical cloud work function
c
!     do i = 1, im
!       if(cnvflg(i)) then
!         if(pfld(i,ktcon(i)) < pcrit(15))then
!           acrt(i)=acrit(15)*(975.-pfld(i,ktcon(i)))
!    &              /(975.-pcrit(15))
!         else if(pfld(i,ktcon(i)) > pcrit(1))then
!           acrt(i)=acrit(1)
!         else
!           k =  int((850. - pfld(i,ktcon(i)))/50.) + 2
!           k = min(k,15)
!           k = max(k,2)
!           acrt(i)=acrit(k)+(acrit(k-1)-acrit(k))*
!    &           (pfld(i,ktcon(i))-pcrit(k))/(pcrit(k-1)-pcrit(k))
!         endif
!       endif
!     enddo
!     do i = 1, im
!       if(cnvflg(i)) then
!         if(islimsk(i) == 1) then
!           w1 = w1l
!           w2 = w2l
!           w3 = w3l
!           w4 = w4l
!         else
!           w1 = w1s
!           w2 = w2s
!           w3 = w3s
!           w4 = w4s
!         endif
c
c  modify critical cloud workfunction by cloud base vertical velocity
c
!         if(pdot(i) <= w4) then
!           acrtfct(i) = (pdot(i) - w4) / (w3 - w4)
!         elseif(pdot(i) >= -w4) then
!           acrtfct(i) = - (pdot(i) + w4) / (w4 - w3)
!         else
!           acrtfct(i) = 0.
!         endif
!         val1    =            -1.
!         acrtfct(i) = max(acrtfct(i),val1)
!         val2    =             1.
!         acrtfct(i) = min(acrtfct(i),val2)
!         acrtfct(i) = 1. - acrtfct(i)
c
c  modify acrtfct(i) by colume mean rh if rhbar(i) is greater than 80 percent
c
c         if(rhbar(i) >= .8) then
c           acrtfct(i) = acrtfct(i) * (.9 - min(rhbar(i),.9)) * 10.
c         endif
c
c  modify adjustment time scale by cloud base vertical velocity
c
!         dtconv(i) = dt2 + max((1800. - dt2),0.) *
!    &                (pdot(i) - w2) / (w1 - w2)
c         dtconv(i) = max(dtconv(i), dt2)
c         dtconv(i) = 1800. * (pdot(i) - w2) / (w1 - w2)
!
!         dtconv(i) = max(dtconv(i),dtmin)
!         dtconv(i) = min(dtconv(i),dtmax)
c
!       endif
!     enddo
!
!  compute convective turn-over time
!
!> - Following Bechtold et al. (2008) \cite bechtold_et_al_2008, the convective adjustment time (dtconv) is set to be proportional to the convective turnover time, which is computed using the mean updraft velocity (wc) and the cloud depth. It is also proportional to the grid size (gdx).
      do i= 1, im
        if(cnvflg(i)) then
          tem = zi(i,ktcon1(i)) - zi(i,kbcon1(i))
          dtconv(i) = tem / wc(i)
          tfac = 1. + gdx(i) / 75000.
          dtconv(i) = tfac * dtconv(i)
          dtconv(i) = max(dtconv(i),dtmin)
          dtconv(i) = min(dtconv(i),dtmax)
        endif
      enddo
!
!> - Calculate advective time scale (tauadv) using a mean cloud layer wind speed. 
      do i= 1, im
        if(cnvflg(i)) then
          sumx(i) = 0.
          umean(i) = 0.
        endif
      enddo
      do k = 2, km1
        do i = 1, im
          if(cnvflg(i)) then
            if(k >= kbcon1(i) .and. k < ktcon1(i)) then
              dz = zi(i,k) - zi(i,k-1)
              tem = sqrt(u1(i,k)*u1(i,k)+v1(i,k)*v1(i,k))
              umean(i) = umean(i) + tem * dz
              sumx(i) = sumx(i) + dz
            endif
          endif
        enddo
      enddo
      do i= 1, im
        if(cnvflg(i)) then
           umean(i) = umean(i) / sumx(i)
           umean(i) = max(umean(i), 1.)
           tauadv(i) = gdx(i) / umean(i)
        endif
      enddo
!> - From Han et al.'s (2017) \cite han_et_al_2017 equation 6, calculate cloud base mass flux as a function of the mean updraft velcoity for the grid sizes where the quasi-equilibrium assumption of Arakawa-Schubert is not valid any longer.
!!  As discussed in Han et al. (2017) \cite han_et_al_2017 , when dtconv is larger than tauadv, the convective mixing is not fully conducted before the cumulus cloud is advected out of the grid cell. In this case, therefore, the cloud base mass flux is further reduced in proportion to the ratio of tauadv to dtconv.
      do i= 1, im
        if(cnvflg(i) .and. .not.asqecflg(i)) then
          k = kbcon(i)
          rho = po(i,k)*100. / (rd*to(i,k))
          tfac = tauadv(i) / dtconv(i)
          tfac = min(tfac, 1.)
          xmb(i) = tfac*betaw*rho*wc(i)
        endif
      enddo
!> - For the cases where the quasi-equilibrium assumption of Arakawa-Schubert is valid, first calculate the large scale destabilization as in equation 5 of Pan and Wu (1995) \cite pan_and_wu_1995 :
!! \f[
!!  \frac{\partial A}{\partial t}_{LS}=\frac{A^+-cA^0}{\Delta t_{LS}}
!! \f]
!! Here \f$A^0\f$ is set to zero following  Han et al.'s (2017) \cite han_et_al_2017 , implying that the instability is completely eliminated after the convective adjustment time, \f$\Delta t_{LS}\f$. 
      do i= 1, im
        if(asqecflg(i)) then
!         fld(i)=(aa1(i)-acrt(i)*acrtfct(i))/dtconv(i)
          fld(i)=aa1(i)/dtconv(i)
          if(fld(i) <= 0.) then
            asqecflg(i) = .false.
            cnvflg(i) = .false.
          endif
        endif
!> - Calculate the stabilization effect of the convection (per unit cloud base mass flux) as in equation 6 of Pan and Wu (1995) \cite pan_and_wu_1995 :
!! \f[
!! \frac{\partial A}{\partial t}_{cu}=\frac{A^*-A^+}{\Delta t_{cu}}
!! \f]
!! \f$\Delta t_{cu}\f$ is the short timescale of the convection.
        if(asqecflg(i)) then
c         xaa0(i) = max(xaa0(i),0.)
          xk(i) = (xaa0(i) - aa1(i)) / mbdt(i)
          if(xk(i) >= 0.) then
            asqecflg(i) = .false.
            cnvflg(i) = .false.
          endif
        endif
c
c--- kernel, cloud base mass flux
c
!> - The cloud base mass flux (xmb) is then calculated from equation 7 of Pan and Wu (1995) \cite pan_and_wu_1995
!! \f[
!! M_c=\frac{-\frac{\partial A}{\partial t}_{LS}}{\frac{\partial A}{\partial t}_{cu}}
!! \f]
!! 
!!  Again when dtconv is larger than tauadv, the cloud base mass flux is further reduced in proportion to the ratio of tauadv to dtconv.
        if(asqecflg(i)) then
          tfac = tauadv(i) / dtconv(i)
          tfac = min(tfac, 1.)
          xmb(i) = -tfac * fld(i) / xk(i)
!         xmb(i) = min(xmb(i),xmbmax(i))
        endif
      enddo
!!
!> - If the large scale destabilization is less than zero, or the stabilization by the convection is greater than zero, then the scheme returns to the calling routine without modifying the state variables.
      totflg = .true.
      do i=1,im
        totflg = totflg .and. (.not. cnvflg(i))
      enddo
      if(totflg) return
!!
!
!> - For scale-aware parameterization, the updraft fraction (sigmagfm) is first computed as a function of the lateral entrainment rate at cloud base (see Han et al.'s (2017) \cite han_et_al_2017 equation 4 and 5), following the study by Grell and Freitas (2014) \cite grell_and_freitus_2014.
      do i = 1, im
        if(cnvflg(i)) then
          tem = min(max(xlamue(i,kbcon(i)), 7.e-5), 3.e-4)
          tem = 0.2 / tem
          tem1 = 3.14 * tem * tem
          sigmagfm(i) = tem1 / garea(i)
          sigmagfm(i) = max(sigmagfm(i), 0.001)
          sigmagfm(i) = min(sigmagfm(i), 0.999)
        endif
      enddo
!
!> - Then, calculate the reduction factor (scaldfunc) of the vertical convective eddy transport of mass flux as a function of updraft fraction from the studies by Arakawa and Wu (2013) \cite arakawa_and_wu_2013 (also see Han et al.'s (2017) \cite han_et_al_2017 equation 1 and 2). The final cloud base mass flux with scale-aware parameterization is obtained from the mass flux when sigmagfm << 1, multiplied by the reduction factor (Han et al.'s (2017) \cite han_et_al_2017 equation 2).
      do i = 1, im
        if(cnvflg(i)) then
          if (gdx(i) < dxcrtuf) then
            scaldfunc(i) = (1.-sigmagfm(i)) * (1.-sigmagfm(i))
            scaldfunc(i) = max(min(scaldfunc(i), 1.0), 0.)
          else
            scaldfunc(i) = 1.0
          endif
          xmb(i) = xmb(i) * scaldfunc(i)
          xmb(i) = min(xmb(i),xmbmax(i))
        endif
      enddo

!If stochastic physics using cellular automata is .true. then perturb the mass-flux here:

      if(do_ca)then
        do i=1,im
         xmb(i) = xmb(i)*(1.0 + ca_deep(i)*5.)
        enddo
      endif

c
c     transport aerosols if present
c
      if (do_aerosols)
     &  call samfdeepcnv_aerosols(im, ix, km, itc, ntc, ntr, delt,
     &  xlamde, xlamdd, cnvflg, jmin, kb, kmax, kbcon, ktcon, fscav,
     &  edto, xlamd, xmb, c0t, eta, etad, zi, xlamue, xlamud, delp,
     &  qtr, qaero)

c
c  restore to,qo,uo,vo to t1,q1,u1,v1 in case convection stops
c
      do k = 1, km
        do i = 1, im
          if (cnvflg(i) .and. k <= kmax(i)) then
            to(i,k) = t1(i,k)
            qo(i,k) = q1(i,k)
            uo(i,k) = u1(i,k)
            vo(i,k) = v1(i,k)
            qeso(i,k) = 0.01 * fpvs(t1(i,k))      ! fpvs is in pa
            qeso(i,k) = eps * qeso(i,k) / (pfld(i,k) + epsm1*qeso(i,k))
            val     =             1.e-8
            qeso(i,k) = max(qeso(i,k), val )
          endif
        enddo
      enddo
      do n = 1, ntr
      do k = 1, km
        do i = 1, im
          if (cnvflg(i) .and. k <= kmax(i)) then
            ctro(i,k,n) = ctr(i,k,n)
          endif
        enddo
      enddo
      enddo
c!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
c
c--- feedback: simply the changes from the cloud with unit mass flux
c---           multiplied by  the mass flux necessary to keep the
c---           equilibrium with the larger-scale.
c
!> ## For the "feedback" control, calculate updated values of the state variables by multiplying the cloud base mass flux and the tendencies calculated per unit cloud base mass flux from the static control.
!> - Calculate the temperature tendency from the moist static energy and specific humidity tendencies.
!> - Update the temperature, specific humidity, and horiztonal wind state variables by multiplying the cloud base mass flux-normalized tendencies by the cloud base mass flux.
!> - Accumulate column-integrated tendencies.
      do i = 1, im
        delhbar(i) = 0.
        delqbar(i) = 0.
        deltbar(i) = 0.
        delubar(i) = 0.
        delvbar(i) = 0.
        qcond(i) = 0.
      enddo
      do n = 1, ntr
      do i = 1, im
        delebar(i,n) = 0.
      enddo
      enddo
      do k = 1, km
        do i = 1, im
          if (cnvflg(i) .and. k <= kmax(i)) then
            if(k <= ktcon(i)) then
              dellat = (dellah(i,k) - hvap * dellaq(i,k)) / cp
              t1(i,k) = t1(i,k) + dellat * xmb(i) * dt2
              q1(i,k) = q1(i,k) + dellaq(i,k) * xmb(i) * dt2
!             tem = 1./rcs(i)
!             u1(i,k) = u1(i,k) + dellau(i,k) * xmb(i) * dt2 * tem
!             v1(i,k) = v1(i,k) + dellav(i,k) * xmb(i) * dt2 * tem
              u1(i,k) = u1(i,k) + dellau(i,k) * xmb(i) * dt2
              v1(i,k) = v1(i,k) + dellav(i,k) * xmb(i) * dt2
              dp = 1000. * del(i,k)
              delhbar(i) = delhbar(i) + dellah(i,k)*xmb(i)*dp/g
              delqbar(i) = delqbar(i) + dellaq(i,k)*xmb(i)*dp/g
              deltbar(i) = deltbar(i) + dellat*xmb(i)*dp/g
              delubar(i) = delubar(i) + dellau(i,k)*xmb(i)*dp/g
              delvbar(i) = delvbar(i) + dellav(i,k)*xmb(i)*dp/g
            endif
          endif
        enddo
      enddo
      do n = 1, ntr
         kk = n+2
      do k = 1, km
        do i = 1, im
          if (cnvflg(i) .and. k <= kmax(i)) then
            if(k <= ktcon(i)) then
              ctr(i,k,n) = ctr(i,k,n)+dellae(i,k,n)*xmb(i)*dt2
              delebar(i,n)=delebar(i,n)+dellae(i,k,n)*xmb(i)*dp/g
              qtr(i,k,kk) = ctr(i,k,n)
            endif
          endif
        enddo
      enddo
      enddo
!> - Recalculate saturation specific humidity using the updated temperature.
      do k = 1, km
        do i = 1, im
          if (cnvflg(i) .and. k <= kmax(i)) then
            if(k <= ktcon(i)) then
              qeso(i,k) = 0.01 * fpvs(t1(i,k))      ! fpvs is in pa
              qeso(i,k) = eps * qeso(i,k)/(pfld(i,k) + epsm1*qeso(i,k))
              val     =             1.e-8
              qeso(i,k) = max(qeso(i,k), val )
            endif
          endif
        enddo
      enddo
c
!> - Add up column-integrated convective precipitation by multiplying the normalized value by the cloud base mass flux.
      do i = 1, im
        rntot(i) = 0.
        delqev(i) = 0.
        delq2(i) = 0.
        flg(i) = cnvflg(i)
      enddo
      do k = km, 1, -1
        do i = 1, im
          if (cnvflg(i) .and. k <= kmax(i)) then
            if(k < ktcon(i)) then
              aup = 1.
              if(k <= kb(i)) aup = 0.
              adw = 1.
              if(k >= jmin(i)) adw = 0.
              rain =  aup * pwo(i,k) + adw * edto(i) * pwdo(i,k)
              rntot(i) = rntot(i) + rain * xmb(i) * .001 * dt2
            endif
          endif
        enddo
      enddo
!> - Determine the evaporation of the convective precipitation and update the integrated convective precipitation.
!> - Update state temperature and moisture to account for evaporation of convective precipitation.
!> - Update column-integrated tendencies to account for evaporation of convective precipitation.
      do k = km, 1, -1
        do i = 1, im
          if (k <= kmax(i)) then
            deltv(i) = 0.
            delq(i) = 0.
            qevap(i) = 0.
            if(cnvflg(i) .and. k < ktcon(i)) then
              aup = 1.
              if(k <= kb(i)) aup = 0.
              adw = 1.
              if(k >= jmin(i)) adw = 0.
              rain =  aup * pwo(i,k) + adw * edto(i) * pwdo(i,k)
              rn(i) = rn(i) + rain * xmb(i) * .001 * dt2
            endif
            if(flg(i) .and. k < ktcon(i)) then
              evef = edt(i) * evfact
              if(islimsk(i) == 1) evef=edt(i) * evfactl
!             if(islimsk(i) == 1) evef=.07
c             if(islimsk(i) == 1) evef = 0.
              qcond(i) = evef * (q1(i,k) - qeso(i,k))
     &                 / (1. + el2orc * qeso(i,k) / t1(i,k)**2)
              dp = 1000. * del(i,k)
              if(rn(i) > 0. .and. qcond(i) < 0.) then
                qevap(i) = -qcond(i) * (1.-exp(-.32*sqrt(dt2*rn(i))))
                qevap(i) = min(qevap(i), rn(i)*1000.*g/dp)
                delq2(i) = delqev(i) + .001 * qevap(i) * dp / g
              endif
              if(rn(i) > 0. .and. qcond(i) < 0. .and.
     &           delq2(i) > rntot(i)) then
                qevap(i) = 1000.* g * (rntot(i) - delqev(i)) / dp
                flg(i) = .false.
              endif
              if(rn(i) > 0. .and. qevap(i) > 0.) then
                q1(i,k) = q1(i,k) + qevap(i)
                t1(i,k) = t1(i,k) - elocp * qevap(i)
                rn(i) = rn(i) - .001 * qevap(i) * dp / g
                deltv(i) = - elocp*qevap(i)/dt2
                delq(i) =  + qevap(i)/dt2
                delqev(i) = delqev(i) + .001*dp*qevap(i)/g
              endif
              delqbar(i) = delqbar(i) + delq(i)*dp/g
              deltbar(i) = deltbar(i) + deltv(i)*dp/g
            endif
          endif
        enddo
      enddo
cj
!     do i = 1, im
!     if(me == 31 .and. cnvflg(i)) then
!     if(cnvflg(i)) then
!       print *, ' deep delhbar, delqbar, deltbar = ',
!    &             delhbar(i),hvap*delqbar(i),cp*deltbar(i)
!       print *, ' deep delubar, delvbar = ',delubar(i),delvbar(i)
!       print *, ' precip =', hvap*rn(i)*1000./dt2
!       print*,'pdif= ',pfld(i,kbcon(i))-pfld(i,ktcon(i))
!     endif
!     enddo
c
c  precipitation rate converted to actual precip
c  in unit of m instead of kg
c
      do i = 1, im
        if(cnvflg(i)) then
c
c  in the event of upper level rain evaporation and lower level downdraft
c    moistening, rn can become negative, in this case, we back out of the
c    heating and the moistening
c
          if(rn(i) < 0. .and. .not.flg(i)) rn(i) = 0.
          if(rn(i) <= 0.) then
            rn(i) = 0.
          else
            ktop(i) = ktcon(i)
            kbot(i) = kbcon(i)
            kcnv(i) = 1
            cldwrk(i) = aa1(i)
          endif
        endif
      enddo
c
c  convective cloud water
c
!> - Calculate convective cloud water.
      do k = 1, km
        do i = 1, im
          if (cnvflg(i) .and. rn(i) > 0.) then
            if (k >= kbcon(i) .and. k < ktcon(i)) then
              cnvw(i,k) = cnvwt(i,k) * xmb(i) * dt2
            endif
          endif
        enddo
      enddo
c
c  convective cloud cover
c
!> - Calculate convective cloud cover, which is used when pdf-based cloud fraction is used (i.e., pdfcld=.true.).
      do k = 1, km
        do i = 1, im
          if (cnvflg(i) .and. rn(i) > 0.) then
            if (k >= kbcon(i) .and. k < ktcon(i)) then
              cnvc(i,k) = 0.04 * log(1. + 675. * eta(i,k) * xmb(i)) 
              cnvc(i,k) = min(cnvc(i,k), 0.6)
              cnvc(i,k) = max(cnvc(i,k), 0.0)
            endif
          endif
        enddo
      enddo
c
c  cloud water
c
!> - Separate detrained cloud water into liquid and ice species as a function of temperature only.
      if (ncloud > 0) then
!
      do k = 1, km
        do i = 1, im
          if (cnvflg(i) .and. rn(i) > 0.) then
!           if (k > kb(i) .and. k <= ktcon(i)) then
            if (k >= kbcon(i) .and. k <= ktcon(i)) then
              tem  = dellal(i,k) * xmb(i) * dt2
              tem1 = max(0.0, min(1.0, (tcr-t1(i,k))*tcrf))
              if (qtr(i,k,2) > -999.0) then
                qtr(i,k,1) = qtr(i,k,1) + tem * tem1            ! ice
                qtr(i,k,2) = qtr(i,k,2) + tem *(1.0-tem1)       ! water
              else
                qtr(i,k,1) = qtr(i,k,1) + tem
              endif
            endif
          endif
        enddo
      enddo
!
      endif
c
!> - If convective precipitation is zero or negative, reset the updated state variables back to their original values (negating convective changes).
      do k = 1, km
        do i = 1, im
          if(cnvflg(i) .and. rn(i) <= 0.) then
            if (k <= kmax(i)) then
              t1(i,k) = to(i,k)
              q1(i,k) = qo(i,k)
              u1(i,k) = uo(i,k)
              v1(i,k) = vo(i,k)
            endif
          endif
        enddo
      enddo
      do n = 1, ntr
         kk = n+2
      do k = 1, km
        do i = 1, im
          if(cnvflg(i) .and. rn(i) <= 0.) then
            if (k <= kmax(i)) then
              ctr(i,k,n)= ctro(i,k,n)
              qtr(i,k,kk)= ctr(i,k,n)
            endif
          endif
        enddo
      enddo
      enddo

!> - Store aerosol concentrations if present
      if (do_aerosols) then
        do n = 1, ntc
          kk = n + itc - 1
          do k = 1, km
            do i = 1, im
              if(cnvflg(i) .and. rn(i) > 0.) then
                if (k <= kmax(i)) qtr(i,k,kk) = qaero(i,k,n)
              endif
            enddo
          enddo
        enddo
       endif
!
! hchuang code change
!
!> - Calculate and retain the updraft and downdraft mass fluxes for dust transport by cumulus convection.
!
!> - Calculate the updraft convective mass flux.
      do k = 1, km
        do i = 1, im
          if(cnvflg(i) .and. rn(i) > 0.) then
            if(k >= kb(i) .and. k < ktop(i)) then
              ud_mf(i,k) = eta(i,k) * xmb(i) * dt2
            endif
          endif
        enddo
      enddo
!> - save the updraft convective mass flux at cloud top.
      do i = 1, im
        if(cnvflg(i) .and. rn(i) > 0.) then
           k = ktop(i)-1
           dt_mf(i,k) = ud_mf(i,k)
        endif
      enddo
!> - Calculate the downdraft convective mass flux.
      do k = 1, km
        do i = 1, im
          if(cnvflg(i) .and. rn(i) > 0.) then
            if(k >= 1 .and. k <= jmin(i)) then
              dd_mf(i,k) = edto(i) * etad(i,k) * xmb(i) * dt2
            endif
          endif
        enddo
      enddo
!
!   include TKE contribution from deep convection
!
      if (ntk > 0) then
!
      do k = 2, km1
        do i = 1, im
          if(cnvflg(i) .and. rn(i) > 0.) then
            if(k > kb(i) .and. k < ktop(i)) then
              tem = 0.5 * (eta(i,k-1) + eta(i,k)) * xmb(i)
              tem1 = pfld(i,k) * 100. / (rd * t1(i,k))
              sigmagfm(i) = max(sigmagfm(i), betaw)
              ptem = tem / (sigmagfm(i) * tem1)
              qtr(i,k,ntk)=qtr(i,k,ntk)+0.5*sigmagfm(i)*ptem*ptem
            endif
          endif
        enddo
      enddo
!
      do k = 2, km1
        do i = 1, im
          if(cnvflg(i) .and. rn(i) > 0.) then
            if(k > 1 .and. k <= jmin(i)) then
              tem = 0.5*edto(i)*(etad(i,k-1)+etad(i,k))*xmb(i)
              tem1 = pfld(i,k) * 100. / (rd * t1(i,k))
              sigmagfm(i) = max(sigmagfm(i), betaw)
              ptem = tem / (sigmagfm(i) * tem1)
              qtr(i,k,ntk)=qtr(i,k,ntk)+0.5*sigmagfm(i)*ptem*ptem
            endif
          endif
        enddo
      enddo
!
      endif
!!
      if(mp_phys == 10) then
        do k=1,km
          do i=1,im
            QLCN(i,k)     = qtr(i,k,2) - qlcn(i,k)
            QICN(i,k)     = qtr(i,k,1) - qicn(i,k)
            cf_upi(i,k)   = cnvc(i,k)
            w_upi(i,k)    = ud_mf(i,k)*t1(i,k)*rd /
     &                     (dt2*max(sigmagfm(i),1.e-12)*prslp(i,k))
            CNV_MFD(i,k)  = ud_mf(i,k)/dt2
            CLCN(i,k)     = cnvc(i,k)
            CNV_FICE(i,k) = QICN(i,k)
     &                    / max(1.e-10,QLCN(i,k)+QICN(i,k))
          enddo
        enddo
      endif
      return
      end


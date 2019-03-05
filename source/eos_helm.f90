!***********************************************************************
! Interface to HELMHOLTZ EoS for XNet 6.0 7/6/2010
! This file contains routines which calculate EoS quantites needed to
! calculate screening corrections for reaction rates.
!***********************************************************************

Subroutine eos_initialize
!-----------------------------------------------------------------------
! This routine initializes the Helmholtz EoS
!-----------------------------------------------------------------------
call read_helm_table
End Subroutine eos_initialize


Subroutine eos_cv(rho,t9,y,cv)
  Use nuclear_data
  Use constants
  Use controls
  include 'vector_eos.dek'
  Real(8), Intent(in) :: t9,rho,y(ny)
  Real(8), Intent(out) :: cv
  Real(8) :: ye,ytot,abar,zbar,z2bar,zibar

! Call the eos if it hasn't already been called for screening
  If(iscrn<=0) Then

! Calculate Ye and other needed moments of the abundance distribution
    call y_moment(y,ye,ytot,abar,zbar,z2bar,zibar)  

! Load input variables for the eos 
    jlo_eos=1
    jhi_eos=1
    den_row(1)=rho
    temp_row(1)=t9*1e9
    abar_row(1)=abar
    zbar_row(1)=ye*abar

    call helmeos
  EndIf

! Convert units from ergs/g to MeV/nucleon and K to GK
  cv=cv_row(1)*1.0d9/epmev/avn

  If(idiag>0) Write(lun_diag,'(a,5es12.5)') 'CV',t9,rho,zbar_row(1)/abar_row(1),cv

  Return
End Subroutine eos_cv

Subroutine eos_interface(t9,rho,y,ye,ztilde,zinter,lambda0,gammae,dztildedt9)
!-----------------------------------------------------------------------
! This routine calls the Helmholtz EOS with the input temperature, 
! density and composition.  It returns the factors needed for screening.
!-----------------------------------------------------------------------
  Use constants
  Use controls
  include 'vector_eos.dek'
  Real(8), Intent(in) :: t9, rho, y(*)
  Real(8), Intent(out) :: ztilde, zinter, lambda0, gammae, ye, dztildedt9
  Real(8) :: ytot,bkt,abar,zbar,z2bar,zibar
  Real(8) :: etae,sratio,efermkt,rel_ef,emass,efc,ae,dsratiodeta
  Real(8) :: onethird=1./3.,twothird=2./3.

! Calculate Ye and other needed moments of the abundance distribution
  call y_moment(y,ye,ytot,abar,zbar,z2bar,zibar)  

! Load input variables for the eos 
  jlo_eos=1
  jhi_eos=1
  den_row(1)=rho
  temp_row(1)=t9*1e9
  abar_row(1)=abar
  zbar_row(1)=ye*abar

! Call the eos
  call helmeos
  etae=etaele_row(1) 
  
! Calculate electon distribution
  bkt=bok*T9 
  emass=ele_en/clt**2
  rel_ef=hbar*(3.0*pi**2*rho*avn*ye)**onethird/(emass*clt)
  efermkt=ele_en*(sqrt(1+rel_ef**2)-1)/bkt
  efc=.5*hbar**2*(3.0*pi**2*rho*avn*ye)**twothird/(emass*bkt)
 !Write(lun_diag,'(a4,6es12.5)') 'MUh',bkt,etae,efermkt,efc,rel_ef

! Calculate ratio f'/f for electrons (Salpeter, Eq. 24)
  call salpeter_ratio(etae,sratio,dsratiodeta)
  ztilde=sqrt(z2bar+zbar*sratio)
  If(iheat>0) Then
    dztildedt9=0.5*zbar/ztilde * dsratiodeta*detat_row(1)*1e9
  Else
    dztildedt9=0.0
  EndIf
  
! Calculate plasma quantities
  lambda0=sqrt(4*pi*rho*avn*ytot)*(e2/bkt)**1.5 ! DGC, Eq. 3
  ae=(3./(4.*pi*avn*rho*ye))**onethird ! electron-sphere radius
  gammae=e2/(ae*bkt) ! electron Coulomb coupling parameter 
  zinter=zibar/(ztilde**.58*zbar**.28)
  If(idiag>0) Write(lun_diag,'(a14,9es12.5)') 'Helmholtz EOS', t9, rho, ye,z2bar,zbar,sratio, ztilde, ztilde*lambda0, gammae
  
  Return
End Subroutine eos_interface

Subroutine salpeter_ratio(eta,ratio,dratiodeta)
!-----------------------------------------------------------------------------
! This routine calculates the salpeter (1954) ratio f'/f(eta) needed for 
! electron screening.  eta is the ratio of electron chemical potential 
! to kT. 
!
! Calculation uses Fermi function relation d/dx f_(k+1) = (k+1) f_k and 
! the rational function expansions of Fukushima (2015; AMC 259 708) for the
! Fermi-Dirac integrals of order 1/2, -1/2, and -3/2.
!-----------------------------------------------------------------------------
  Use controls
  
  Integer :: i
  Real(8) :: eta,fermip,fermim,ratio,dratiodeta
  Real(8) :: dfmdeta,dfpdeta
  Real(8) :: fdm3h,fdm1h,fd1h

  fermim = fdm1h(eta)
  fermip = fd1h(eta)

! Evalutate the salpeter ratio
  ratio = 0.5 * fermim/fermip
  If(iheat>0) Then
    dfmdeta = -0.5 * fdm3h(eta)
    dfpdeta = 0.5*fermim
    dratiodeta = ratio * (dfmdeta/fermim - dfpdeta/fermip)
  Else
    dratiodeta = 0.0
  EndIf
! write(lun_diag,"(1x,4es12.4)") eta,ratio,fermim,fermip
  Return
End Subroutine salpeter_ratio

Subroutine y_moment(y,ye,ytot,abar,zbar,z2bar,zibar)  
!------------------------------------------------------------------------------  
! This routine calculates moments of the abundance distribution for the EOS.
!------------------------------------------------------------------------------  
  Use nuclear_data
  Use controls
  Real(8), Intent(in)  :: y(ny)
  Real(8), Intent(out) :: ye,ytot,abar,zbar,z2bar,zibar
  Real(8)              :: atot,ztot

! Calculate abundance moments
  ytot =sum(y(:))
  atot =sum(aa*y)
  ztot =sum(zz*y)
  abar =atot/ytot
  zbar =ztot/ytot
  z2bar=sum(zz*zz*y)/ytot
  zibar=sum(zz**1.58*y)/ytot
  ye=ztot
  If(idiag>0) Write(lun_diag,'(a4,6es12.5)') 'YMom',ytot,abar,zbar,z2bar,zibar,ye
  
  Return 
End Subroutine y_moment

Real(8) Function fdm3h(x)
! Double precision rational minimax approximation of Fermi-Dirac integral of order k=-3/2
! Reference: Fukushima, T. (2014, submitted to App. Math. Comp.) 
! Author: Fukushima, T. <Toshio.Fukushima@nao.ac.jp>
  Real(8) x,ex,t,w,s,fd,factor
  Parameter (factor=-2.d0)    ! = 1/(k+1)
  If(x<-2.d0) Then
    ex=exp(x)
    t=ex*7.38905609893065023d0
    fd=ex*(-3.54490770181103205d0 &
    +ex*(82737.595643818605d0 &
    +t*(18481.5553495836940d0 &
    +t*(1272.73919064487495d0 &
    +t*(26.3420403338352574d0 &
    -t*0.00110648970639283347d0 &
    ))))/(16503.7625405383183d0 &
    +t*(6422.0552658801394d0 &
    +t*(890.85389683932154d0 &
    +t*(51.251447078851450d0 &
    +t)))))
  ElseIf(x<0.d0) Then
    s=-0.5d0*x
    t=1.d0-s
    fd=-(946.638483706348559d0 &
    +t*(76.3328330396778450d0 &
    +t*(62.7809183134124193d0 &
    +t*(83.8442376534073219d0 &
    +t*(23.2285755924515097d0 &
    +t*(3.21516808559640925d0 &
    +t*(1.58754232369392539d0 &
    +t*(0.687397326417193593d0 &
    +t*0.111510355441975495d0 &
    ))))))))/(889.4123665319664d0 &
    +s*(126.7054690302768d0 &
    +s*(881.4713137175090d0 &
    +s*(108.2557767973694d0 &
    +s*(289.38131234794585d0 &
    +s*(27.75902071820822d0 &
    +s*(34.252606975067480d0 &
    +s*(1.9592981990370705d0 &
    +s))))))))
  ElseIf(x<2.d0) Then
    t=0.5d0*x
    fd=-(754.61690882095729d0 &
    +t*(565.56180911009650d0 &
    +t*(494.901267018948095d0 &
    +t*(267.922900418996927d0 &
    +t*(110.418683240337860d0 &
    +t*(39.4050164908951420d0 &
    +t*(10.8654460206463482d0 &
    +t*(2.11194887477009033d0 &
    +t*0.246843599687496060d0 &
    ))))))))/(560.03894899770103d0 &
    +t*(70.007586553114572d0 &
    +t*(582.42052644718871d0 &
    +t*(56.181678606544951d0 &
    +t*(205.248662395572799d0 &
    +t*(12.5169006932790528d0 &
    +t*(27.2916998671096202d0 &
    +t*(0.53299717876883183d0 &
    +t))))))))
  ElseIf(x<5.d0) Then
    t=0.3333333333333333333d0*(x-2.d0)
    fd=-(526.022770226139287d0 &
    +t*(631.116211478274904d0 &
    +t*(516.367876532501329d0 &
    +t*(267.894697896892166d0 &
    +t*(91.3331816844847913d0 &
    +t*(17.5723541971644845d0 &
    +t*(1.46434478819185576d0 &
    +t*(1.29615441010250662d0 &
    +t*0.223495452221465265d0 &
    ))))))))/(354.867400305615304d0 &
    +t*(560.931137013002977d0 &
    +t*(666.070260050472570d0 &
    +t*(363.745894096653220d0 &
    +t*(172.272943258816724d0 &
    +t*(23.7751062504377332d0 &
    +t*(12.5916012142616255d0 &
    +t*(-0.888604976123420661d0 &
    +t))))))))
  ElseIf(x<10.d0) Then
    t=0.2d0*x-1.d0
    fd=-(18.0110784494455205d0 &
    +t*(36.1225408181257913d0 &
    +t*(38.4464752521373310d0 &
    +t*(24.1477896166966673d0 &
    +t*(9.27772356782901602d0 &
    +t*(2.49074754470533706d0 &
    +t*(0.163824586249464178d0 &
    -t*0.00329391807590771789d0 &
    )))))))/(18.8976860386360201d0 &
    +t*(49.3696375710309920d0 &
    +t*(60.9273314194720251d0 &
    +t*(43.6334649971575003d0 &
    +t*(20.6568810936423065d0 &
    +t*(6.11094689399482273d0 &
    +t))))))
  ElseIf(x<20.d0) Then
    t=0.1d0*x-1.d0
    fd=-(4.10698092142661427d0 &
    +t*(17.1412152818912658d0 &
    +t*(32.6347877674122945d0 &
    +t*(36.6653101837618939d0 &
    +t*(25.9424894559624544d0 &
    +t*(11.2179995003884922d0 &
    +t*(2.30099511642112478d0 &
    +t*(0.0928307248942099967d0 &
    -t*0.00146397877054988411d0 &
    ))))))))/(6.40341731836622598d0 &
    +t*(30.1333068545276116d0 &
    +t*(64.0494725642004179d0 &
    +t*(80.5635003792282196d0 &
    +t*(64.9297873014508805d0 &
    +t*(33.3013900893183129d0 &
    +t*(9.61549304470339929d0 &
    +t)))))))
  ElseIf(x<40.d0) Then
    t=0.05d0*x-1.d0
    fd=-(95.2141371910496454d0 &
    +t*(420.050572604265456d0 &
    +t*(797.778374374075796d0 &
    +t*(750.378359146985564d0 &
    +t*(324.818150247463736d0 &
    +t*(50.3115388695905757d0 &
    +t*(0.372431961605507103d0 &
    +t*(-0.103162211894757911d0 &
    +t*0.00191752611445211151d0 &
    ))))))))/(212.232981736099697d0 &
    +t*(1043.79079070035083d0 &
    +t*(2224.50099218470684d0 &
    +t*(2464.84669868672670d0 &
    +t*(1392.55318009810070d0 &
    +t*(346.597189642259199d0 &
    +t*(22.7314613168652593d0 &
    -t)))))))
  Else
    w=1.d0/(x*x)
    s=1.d0-1600.d0*w
    fd=factor/sqrt(x)*(1.d0 &
    +w*(12264.3569103180524d0 &
    +s*(3204.34872454052352d0 &
    +s*(140.119604748253961d0 &
    +s*0.523918919699235590d0 &
    )))/(9877.87829948067200d0 &
    +s*(2644.71979353906092d0 &
    +s*(128.863768007644572d0 &
    +s))))
  EndIf
  fdm3h=fd
  Return
End Function fdm3h

Real(8) Function fdm1h(x)
! Double precision rational minimax approximation of Fermi-Dirac integral of order k=-1/2
! Reference: Fukushima, T. (2014, submitted to App. Math. Comp.) 
! Author: Fukushima, T. <Toshio.Fukushima@nao.ac.jp>
  Real(8) x,ex,t,w,s,fd,factor
  Parameter (factor=2.d0)    ! = 1/(k+1)
  If(x<-2.d0) Then
    ex=exp(x)
    t=ex*7.38905609893065023d0
    fd=ex*(1.77245385090551603d0 &
    -ex*(40641.4537510284430d0 &
    +t*(9395.7080940846442d0 &
    +t*(649.96168315267301d0 &
    +t*(12.7972295804758967d0 &
    +t*0.00153864350767585460d0 &
    ))))/(32427.1884765292940d0 &
    +t*(11079.9205661274782d0 &
    +t*(1322.96627001478859d0 &
    +t*(63.738361029333467d0 &
    +t)))))
  ElseIf(x<0.d0) Then
    s=-0.5d0*x
    t=1.d0-s
    fd=(272.770092131932696d0 &
    +t*(30.8845653844682850d0 &
    +t*(-6.43537632380366113d0 &
    +t*(14.8747473098217879d0 &
    +t*(4.86928862842142635d0 &
    +t*(-1.53265834550673654d0 &
    +t*(-1.02698898315597491d0 &
    +t*(-0.177686820928605932d0 &
    -t*0.00377141325509246441d0 &
    ))))))))/(293.075378187667857d0 &
    +s*(305.818162686270816d0 &
    +s*(299.962395449297620d0 &
    +s*(207.640834087494249d0 &
    +s*(92.0384803181851755d0 &
    +s*(37.0164914112791209d0 &
    +s*(7.88500950271420583d0 &
    +s)))))))
  ElseIf(x<2.d0) Then
    t=0.5d0*x
    fd=(3531.50360568243046d0 &
    +t*(6077.5339658420037d0 &
    +t*(6199.7700433981326d0 &
    +t*(4412.78701919567594d0 &
    +t*(2252.27343092810898d0 &
    +t*(811.84098649224085d0 &
    +t*(191.836401053637121d0 &
    +t*23.2881838959183802d0 &
    )))))))/(3293.83702584796268d0 &
    +t*(1528.97474029789098d0 &
    +t*(2568.48562814986046d0 &
    +t*(925.64264653555825d0 &
    +t*(574.23248354035988d0 &
    +t*(132.803859320667262d0 &
    +t*(29.8447166552102115d0 &
    +t)))))))
  ElseIf(x<5.d0) Then
    t=0.3333333333333333333d0*(x-2.d0)
    fd=(4060.70753404118265d0 &
    +t*(10812.7291333052766d0 &
    +t*(13897.5649482242583d0 &
    +t*(10628.4749852740029d0 &
    +t*(5107.70670190679021d0 &
    +t*(1540.84330126003381d0 &
    +t*(284.452720112970331d0 &
    +t*29.5214417358484151d0 &
    )))))))/(1564.58195612633534d0 &
    +t*(2825.75172277850406d0 &
    +t*(3189.16066169981562d0 &
    +t*(1955.03979069032571d0 &
    +t*(828.000333691814748d0 &
    +t*(181.498111089518376d0 &
    +t*(32.0352857794803750d0 &
    +t)))))))
  ElseIf(x<10.d0) Then
    t=0.2d0*x-1.d0
    fd=(1198.41719029557508d0 &
    +t*(3263.51454554908654d0 &
    +t*(3874.97588471376487d0 &
    +t*(2623.13060317199813d0 &
    +t*(1100.41355637121217d0 &
    +t*(267.469532490503605d0 &
    +t*(25.4207671812718340d0 &
    +t*0.389887754234555773d0 &
    )))))))/(273.407957792556998d0 &
    +t*(595.918318952058643d0 &
    +t*(605.202452261660849d0 &
    +t*(343.183302735619981d0 &
    +t*(122.187622015695729d0 &
    +t*(20.9016359079855933d0 &
    +t))))))
  ElseIf(x<20.d0) Then
    t=0.1d0*x-1.d0
    fd=(9446.00169435237637d0 &
    +t*(36843.4448474028632d0 &
    +t*(63710.1115419926191d0 &
    +t*(62985.2197361074768d0 &
    +t*(37634.5231395700921d0 &
    +t*(12810.9898627807754d0 &
    +t*(1981.56896138920963d0 &
    +t*81.4930171897667580d0 &
    )))))))/(1500.04697810133666d0 &
    +t*(5086.91381052794059d0 &
    +t*(7730.01593747621895d0 &
    +t*(6640.83376239360596d0 &
    +t*(3338.99590300826393d0 &
    +t*(860.499043886802984d0 &
    +t*(78.8565824186926692d0 &
    +t)))))))
  ElseIf(x<40.d0) Then
    t=0.05d0*x-1.d0
    fd=(22977.9657855367223d0 &
    +t*(123416.616813887781d0 &
    +t*(261153.765172355107d0 &
    +t*(274618.894514095795d0 &
    +t*(149710.718389924860d0 &
    +t*(40129.3371700184546d0 &
    +t*(4470.46495881415076d0 &
    +t*132.684346831002976d0 &
    )))))))/(2571.68842525335676d0 &
    +t*(12521.4982290775358d0 &
    +t*(23268.1574325055341d0 &
    +t*(20477.2320119758141d0 &
    +t*(8726.52577962268114d0 &
    +t*(1647.42896896769909d0 &
    +t*(106.475275142076623d0 &
    +t)))))))
  Else
    w=1.d0/(x*x)
    t=1600.d0*w
    fd=sqrt(x)*factor*(1.d0 &
    -w*(0.411233516712009968d0 &
    +t*(0.00110980410034088951d0 &
    +t*(0.0000113689298990173683d0 &
    +t*(2.56931790679436797d-7 &
    +t*(9.97897786755446178d-9 &
    +t*8.67667698791108582d-10))))))
  EndIf
  fdm1h=fd
  Return
End Function fdm1h

Real(8) Function fd1h(x)
! Double precision rational minimax approximation of Fermi-Dirac integral of order k=1/2
! Reference: Fukushima, T. (2014, submitted to App. Math. Comp.) 
! Author: Fukushima, T. <Toshio.Fukushima@nao.ac.jp>
  Real(8) x,ex,t,w,s,fd,factor
  Parameter (factor=2.d0/3.d0)    ! = 1/(k+1)
  If(x<-2.d0) Then
    ex=exp(x)
    t=ex*7.38905609893065023d0
    fd=ex*(0.886226925452758014d0 &
    -ex*(19894.4553386951666d0 &
    +t*(4509.64329955948557d0 &
    +t*(303.461789035142376d0 &
    +t*(5.7574879114754736d0 &
    +t*0.00275088986849762610d0 &
    ))))/(63493.915041308052d0 &
    +t*(19070.1178243603945d0 &
    +t*(1962.19362141235102d0 &
    +t*(79.250704958640158d0 &
    +t)))))
  ElseIf(x<0.d0) Then
    s=-0.5d0*x
    t=1.d0-s
    fd=(149.462587768865243d0 &
    +t*(22.8125889885050154d0 &
    +t*(-0.629256395534285422d0 &
    +t*(9.08120441515995244d0 &
    +t*(3.35357478401835299d0 &
    +t*(-0.473677696915555805d0 &
    +t*(-0.467190913556185953d0 &
    +t*(-0.0880610317272330793d0 &
    -t*0.00262208080491572673d0 &
    ))))))))/(269.94660938022644d0 &
    +s*(343.6419926336247d0 &
    +s*(323.9049470901941d0 &
    +s*(218.89170769294024d0 &
    +s*(102.31331350098315d0 &
    +s*(36.319337289702664d0 &
    +s*(8.3317401231389461d0 &
    +s)))))))
  ElseIf(x<2.d0) Then
    t=0.5d0*x
    fd=(71652.717119215557d0 &
    +t*(134954.734070223743d0 &
    +t*(153693.833350315645d0 &
    +t*(123247.280745703400d0 &
    +t*(72886.293647930726d0 &
    +t*(32081.2499422362952d0 &
    +t*(10210.9967337762918d0 &
    +t*(2152.71110381320778d0 &
    +t*232.906588165205042d0 &
    ))))))))/(105667.839854298798d0 &
    +t*(31946.0752989314444d0 &
    +t*(71158.788776422211d0 &
    +t*(15650.8990138187414d0 &
    +t*(13521.8033657783433d0 &
    +t*(1646.98258283527892d0 &
    +t*(618.90691969249409d0 &
    +t*(-3.36319591755394735d0 &
    +t))))))))
  ElseIf(x<5.d0) Then
    t=0.3333333333333333333d0*(x-2.d0)
    fd=(23744.8706993314289d0 &
    +t*(68257.8589855623002d0 &
    +t*(89327.4467683334597d0 &
    +t*(62766.3415600442563d0 &
    +t*(20093.6622609901994d0 &
    +t*(-2213.89084119777949d0 &
    +t*(-3901.66057267577389d0 &
    -t*948.642895944858861d0 &
    )))))))/(9488.61972919565851d0 &
    +t*(12514.8125526953073d0 &
    +t*(9903.44088207450946d0 &
    +t*(2138.15420910334305d0 &
    +t*(-528.394863730838233d0 &
    +t*(-661.033633995449691d0 &
    +t*(-51.4481470250962337d0 &
    +t)))))))
  ElseIf(x<10.d0) Then
    t=0.2d0*x-1.d0
    fd=(311337.452661582536d0 &
    +t*(1.11267074416648198d6 &
    +t*(1.75638628895671735d6 &
    +t*(1.59630855803772449d6 &
    +t*(910818.935456183774d0 &
    +t*(326492.733550701245d0 &
    +t*(65507.2624972852908d0 &
    +t*4809.45649527286889d0 &
    )))))))/(39721.6641625089685d0 &
    +t*(86424.7529107662431d0 &
    +t*(88163.7255252151780d0 &
    +t*(50615.7363511157353d0 &
    +t*(17334.9774805008209d0 &
    +t*(2712.13170809042550d0 &
    +t*(82.2205828354629102d0 &
    -t)))))))*0.999999999999999877d0
  ElseIf(x<20.d0) Then
    t=0.1d0*x-1.d0
    fd=(7.26870063003059784d6 &
    +t*(2.79049734854776025d7 &
    +t*(4.42791767759742390d7 &
    +t*(3.63735017512363365d7 &
    +t*(1.55766342463679795d7 &
    +t*(2.97469357085299505d6 &
    +t*154516.447031598403d0 &
    ))))))/(340542.544360209743d0 &
    +t*(805021.468647620047d0 &
    +t*(759088.235455002605d0 &
    +t*(304686.671371640343d0 &
    +t*(39289.4061400542309d0 &
    +t*(582.426138126398363d0 &
    +t*(11.2728194581586028d0 &
    -t)))))))
  ElseIf(x<40.d0) Then
    t=0.05d0*x-1.d0
    fd=(4.81449797541963104d6 &
    +t*(1.85162850713127602d7 &
    +t*(2.77630967522574435d7 &
    +t*(2.03275937688070624d7 &
    +t*(7.41578871589369361d6 &
    +t*(1.21193113596189034d6 &
    +t*63211.9545144644852d0 &
    ))))))/(80492.7765975237449d0 &
    +t*(189328.678152654840d0 &
    +t*(151155.890651482570d0 &
    +t*(48146.3242253837259d0 &
    +t*(5407.08878394180588d0 &
    +t*(112.195044410775577d0 &
    -t))))))
  Else
    w=1.d0/(x*x)
    s=1.d0-1600.d0*w
    fd=x*sqrt(x)*0.666666666666666667d0*(1.d0+w &
    *(8109.79390744477921d0 &
    +s*(342.069867454704106d0 &
    +s*1.07141702293504595d0)) &
    /(6569.98472532829094d0 &
    +s*(280.706465851683809d0 &
    +s)))
  EndIf
  fd1h=fd
  Return
End Function fd1h

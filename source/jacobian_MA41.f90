!*******************************************************************************
! Jacobian Sparce for MA41, part of XNet 7, 6/2/10
!
! The routines in this file are used to replace the standard dense Jacobian 
! and associated solver with the Harwell MA41 sparse solver package.  
!
! The bulk of the computational cost of the network (60-95%) is the solving 
! of the matrix equation.  Careful selection of the matrix solver is therefore 
! very important to fast computation.  For networks from a few dozen up to a 
! couple hundred species, hand tuned dense solvers such as those supplied by the 
! hardware manufacturer (often LAPACK) or third-parties like NAG, IMSL, etc. are 
! the fastest. However for larger matrices, sparse solvers are faster.  MA41 is 
! a solver from the Harwell Subroutine Library, which is available under an
! academic license.  It assumes a matrix sparsity pattern which is nearly symmetric,
! but with unsymmetric values. It can be faster than MA48/PARDISO for cases with
! very few factorizations per analysis step (i.e. few timesteps).
!*******************************************************************************

Module jacobian_data
!===============================================================================
! Contains data for use in the sparse solver.
!===============================================================================
  Use nuclear_data
  Real(8), Dimension(:), Allocatable :: tvals,sident,work
  Integer, Dimension(:), Allocatable :: ridx,cidx,irn,jcn
  Integer, Dimension(:), Allocatable :: ns11,ns21,ns22,ns31,ns32,ns33
  Integer, Dimension(:), Allocatable :: iwork
  Integer :: icntl(20),keep(50),info(20)
  Real(8) :: cntl(10),rinfo(20),maxerr
  Integer :: nnz,job_decmp,job_solve,maxiw,maxw,msize
  Integer :: lval,l1s,l2s,l3s
!$OMP THREADPRIVATE(tvals,jcn,irn,iwork,work,maxiw,maxw,keep,info,rinfo,cntl,icntl,job_decmp,job_solve)

  Real(8), Dimension(:), Allocatable :: mc29r,mc29c
!$OMP THREADPRIVATE(mc29r,mc29c)
End Module jacobian_data
  
Subroutine read_jacobian_data(data_dir)
!===============================================================================
! Reads in data necessary to use sparse solver and initializes the Jacobian data.
!===============================================================================
  Use controls
  Use reac_rate_data
  Use jacobian_data
       
  Character (LEN=*),  Intent(in)  :: data_dir
  Integer :: i,pb(ny+1)
  
  Open(600,file=trim(data_dir)//"/sparse_ind",status='old',form='unformatted')

  Read(600) lval
  If(iheat>0) Then
    nnz=lval+2*ny+1
    msize=ny+1
  Else
    nnz=lval
    msize=ny
  EndIf

  Allocate(ridx(nnz),cidx(nnz),sident(nnz))
  Read(600) ridx(1:lval),cidx(1:lval),pb
  If(iheat>0) Then
! Add jacobian indices for temperature coupling
    Do i=1,ny
      cidx(i+lval) = ny+1    ! Extra column
      ridx(i+lval) = i
     
      cidx(i+lval+ny) = i    ! Extra row
      ridx(i+lval+ny) = ny+1
    EndDo
    cidx(lval+2*ny+1) = ny+1 ! dT9dot/dT9 term
    ridx(lval+2*ny+1) = ny+1
  EndIf

  Read(600) l1s,l2s,l3s
  
! Build  arrays for direct sparse representation Jacobian build
  Allocate(ns11(l1s))
  Allocate(ns21(l2s),ns22(l2s))
  Allocate(ns31(l3s),ns32(l3s),ns33(l3s))
  
  ns11 = 0
  ns21 = 0
  ns22 = 0
  ns31 = 0
  ns32 = 0
  ns33 = 0
  
  Read(600) ns11,ns21,ns22
  Read(600) ns31
  Read(600) ns32
  Read(600) ns33
  Close(600)  
  
! Build a compressed row format version of the identity matrix
  sident=0.0
  Do i=1,nnz
    If (ridx(i)==cidx(i)) sident(i)=1.0
  EndDo
  
!$OMP PARALLEL DEFAULT(SHARED)
! Set default values for MA41 control parameters
  Call MA41ID(cntl,icntl,keep)

! Set error/diagnostic output to XNet diagnostic file (default=6)
  icntl(1) = lun_diag
  If(idiag>=1) icntl(2) = lun_diag

! Set statistics output (default=0)
  If(idiag>=2) icntl(3) = lun_diag

! Set level of MA41 error/diagnostic output (default=2)
  If(idiag>=4) icntl(4) = 3

! Set the number of processors (default=1)
! icntl(5) = 2

! Use a maximum transversal algorithm to get a zero-free diagonal (default=0)
! icntl(6) = 1

! Use custom pivot order (must set the variable iwork manually) (default=0)
! icntl(7) = 1

! Scaling strategy (default=0 (no scaling))
! icntl(8) = 1

! Solve A*x = b (default=1), or A^T*x = b
! icntl(9) = 0

! Maximum number of steps of iterative refinement (default=0)
! icntl(10) = 10

! Return the infinity norm, solution, scaled residual, backward error estimates, forward error estimates to rinfo(4:9) (default=0)
! icntl(11) = 1

! Set the pivoting threshold (near 0.0 emphasizes sparsity; near 1.0 emphasizes stability) (default=0.01)
! cntl(1) = 0.0

! This holds the jacobian matrix
  Allocate(tvals(nnz))
  
! These are variables to be used by the MA41 solver
  Allocate(jcn(nnz),irn(nnz))
  If(icntl(7)==1) Then
    maxiw = nnz + 12*msize + 1
  Else
    maxiw = 2*nnz + 12*msize + 1
  EndIf
  maxw = 2*maxiw
  Allocate(iwork(maxiw),work(maxw))

! These are variables to be used by MC29 if scaling is deemed necessary
  If(icntl(8)/=0) Then
    Allocate(mc29r(msize),mc29c(msize))
  Else
    Allocate(mc29r(1),mc29c(1))
  EndIf
  mc29r = 0.0
  mc29c = 0.0
!$OMP END PARALLEL

! Set the value for the maximum allowed error in the call to MA41AD w/ job = 3,5,6 and icntl(11)>0
  maxerr = 1.0d-11
  
End Subroutine read_jacobian_data

Subroutine jacobian_build(diag,mult)
!===============================================================================
! This routine calculates the Jacobian matrix dYdot/dY, and and augments 
! by multiplying all elements by mult and adding diag to the diagonal elements.
!===============================================================================
  Use controls
  Use conditions
  Use abundances
  Use reac_rate_data
  Use cross_sect_data
  Use jacobian_data
  Use timers
  
  Real(8), Intent(in) :: diag, mult
  Integer :: i,j,kstep,i0,la1,le1,la2,le2,la3,le3,j1,l1,l2,l3
  Integer :: ls1,ls2,ls3
  Real(8) :: dydotdt9(ny),dt9dotdy(ny)
  
! Initiate timer
  start_timer = xnet_wtime()
  timer_jacob = timer_jacob - start_timer  

! The quick solution to taking advantage of sparseness is to create a values array that has the maximum
! number of non-zero elements as well as a 2-by-#non-zero elements matrix and the other vectors
! required by the sparse solver.  The second matrix will contain the ordered pairs that map to a 
! particular place in the Jacobian.  Build the Jacobian as it is built now, Then pull the values 
! from it using the ordered pairs to fill the values array. 

! Build the Jacobian, species by species
  tvals = 0.0

  Do i0=1,ny
    la1=la(1,i0)
    le1=le(1,i0)
    Do j1=la1,le1
      ls1 = ns11(j1) ! ns11(j1) gives the index effected reaction j1 by in the compressed row storage scheme
      tvals(ls1)=tvals(ls1)+b1(j1)
    EndDo
    la2=la(2,i0) 
    le2=le(2,i0)  
    Do j1=la2,le2
      ls1=ns21(j1) ! ns21(j1) gives the first index effected reaction j1 by in the compressed row storage scheme
      ls2=ns22(j1) ! ns22(j1) gives the second index effected reaction j1 by in the compressed row storage scheme
      l1=n21(j1)   ! n21(k) gives the index of first reactant in reaction mu2(k)
      l2=n22(j1)   ! n22(k) gives the index of second reactant in reaction mu2(k)
      tvals(ls1)=tvals(ls1)+b2(j1)*yt(l2)
      tvals(ls2)=tvals(ls2)+b2(j1)*yt(l1)
    EndDo
    la3=la(3,i0)
    le3=le(3,i0)
    Do j1=la3,le3
      ls1=ns31(j1) ! ns31(j1) gives the first index effected reaction j1 by in the compressed row storage scheme
      ls2=ns32(j1) ! ns32(j1) gives the second index effected reaction j1 by in the compressed row storage scheme
      ls3=ns33(j1) ! ns33(j1) gives the third index effected reaction j1 by in the compressed row storage scheme
      l1=n31(j1)   ! n21(k) gives the index of first reactant in reaction mu2(k)
      l2=n32(j1)   ! n22(k) gives the index of second reactant in reaction mu2(k)
      l3=n33(j1)   ! n22(k) gives the index of third reactant in reaction mu2(k)
      tvals(ls1)=tvals(ls1)+b3(j1)*yt(l2)*yt(l3)
      tvals(ls2)=tvals(ls2)+b3(j1)*yt(l1)*yt(l3)
      tvals(ls3)=tvals(ls3)+b3(j1)*yt(l1)*yt(l2)
    EndDo
  EndDo

  If(iheat>0) Then

    dr1dt9=a1*dcsect1dt9(mu1)*yt(n11)
    dr2dt9=a2*dcsect2dt9(mu2)*yt(n21)*yt(n22)
    dr3dt9=a3*dcsect3dt9(mu3)*yt(n31)*yt(n32)*yt(n33)

    dydotdt9=0.0
    Do i0=1,ny
      la1=la(1,i0)
      le1=le(1,i0)
      Do j1=la1,le1
        dydotdt9(i0)=dydotdt9(i0)+dr1dt9(j1)
      EndDo
      la2=la(2,i0)
      le2=le(2,i0)
      Do j1=la2,le2
        dydotdt9(i0)=dydotdt9(i0)+dr2dt9(j1)
      EndDo
      la3=la(3,i0)
      le3=le(3,i0)
      Do j1=la3,le3
        dydotdt9(i0)=dydotdt9(i0)+dr3dt9(j1)
      EndDo
    EndDo
    tvals(lval+1:lval+ny)=dydotdt9

    dt9dotdy=0.0
    Do j1=1,lval
      dt9dotdy(cidx(j1))=dt9dotdy(cidx(j1))+mex(ridx(j1))*tvals(j1)/cv
    EndDo
    tvals(lval+ny+1:lval+2*ny)=-dt9dotdy
    tvals(nnz)=-sum(mex*dydotdt9)/cv

  EndIf

! Augment matrix with externally provided factors  
  tvals = mult * tvals
  tvals = tvals + sident * diag 
  
  If(idiag>=5) Then
    Write(lun_diag,"(a9,2es14.7)") 'JAC_build',diag,mult
    Write(lun_diag,"(14es9.1)") tvals
  EndIf

! Stop timer
  stop_timer = xnet_wtime()
  timer_jacob = timer_jacob + stop_timer

  Return   
End Subroutine jacobian_build
  
Subroutine jacobian_solve(kstep,yrhs,dy,t9rhs,dt9) 
!===============================================================================
! This routine solves the system of abundance equations composed of the jacobian
! matrix and rhs vector.
!===============================================================================
  Use controls
  Use jacobian_data
  Use timers
  Integer, Intent(in)  :: kstep
  Real(8), Intent(in)  :: yrhs(ny)
  Real(8), Intent(out) :: dy(ny)
  Real(8), Intent(in)  :: t9rhs
  Real(8), Intent(out) :: dt9
  
  Call jacobian_decomp(kstep)
  Call jacobian_bksub(yrhs,dy,t9rhs,dt9)
  
! Diagnostic output
  If(idiag>=4) Then
    Write(lun_diag,"(a)") 'JAC_SOLV'
    Write(lun_diag,"(14es10.3)") dy
    If(iheat>0) Write(lun_diag,"(es10.3)") dt9
  EndIf

  Return
End Subroutine jacobian_solve                                                                       
  
Subroutine jacobian_decomp(kstep) 
!===============================================================================
! This routine performs a matrix decomposition for the jacobian
!===============================================================================
  Use controls
  Use jacobian_data
  Use timers
  Integer, Intent(in)  :: kstep
  Integer :: i,j,kdecomp 
  Real(8) :: rhs(1)
  
! Initiate timer
  start_timer = xnet_wtime()
  timer_solve = timer_solve - start_timer  
  
! Perform symbolic analysis (job = 1)
  If(kstep == 1) Then
    job_decmp = 1
    jcn = cidx
    irn = ridx

    Do kdecomp=1,5
      info = 0
      rinfo = 0.0
      Call MA41AD(job_decmp,msize,nnz,irn,jcn,tvals,rhs,mc29c,mc29r,keep,iwork,maxiw,work,maxw,cntl,icntl,info,rinfo)

      If(info(1) == 0 .and. info(8) <= maxw .and. info(7) <= maxiw) Then
        job_decmp = 2 ! If analysis is successful, proceed to factorization
        Exit
      ElseIf(kdecomp == 5) Then
        Write(lun_diag,"(1x,a,i5,a,i5,a,i2)") 'Max iters: job=',job_decmp,', kdecomp=',kdecomp,', info(1)=',info(1)
        Stop
      Else
        Write(lun_diag,"(1x,a,i5,a,i5,a,i2)") 'Warning: job=',job_decmp,', kdecomp=',kdecomp,', info(1)=',info(1)

        If(info(1) == -5 .or. info(1) == 4) Then
          Write(lun_diag,"(1x,a,i7,a,i7)") 'Reallocating work array: maxw=',maxw,', info(8)=',max(info(2),info(8))
          maxw = max(info(2),info(8))
          Deallocate(work)
          Allocate(work(maxw))
        ElseIf(info(8) > maxw) Then
          Write(lun_diag,"(1x,a,i7,a,i7)") 'Reallocating work array: maxw=',maxw,', info(8)=',info(8)
          maxw = info(8)
          Deallocate(work)
          Allocate(work(maxw))
        EndIf

        If(info(1) == -7) Then
          Write(lun_diag,"(1x,a,i7,a,i7)") 'Reallocating iwork array: maxiw=',maxiw,', info(7)=',max(info(2),info(7))
          maxiw = max(info(2),info(7))
          Deallocate(iwork)
          Allocate(iwork(maxiw))
        ElseIf(info(7) > maxiw) Then
          Write(lun_diag,"(1x,a,i7,a,i7)") 'Reallocating iwork array: maxiw=',maxiw,', info(7)=',info(7)
          maxiw = info(7)
          Deallocate(iwork)
          Allocate(iwork(maxiw))
        EndIf

      EndIf
    EndDo
  EndIf

  Do kdecomp=1,5
    info = 0
    rinfo = 0.0
    Call MA41AD(job_decmp,msize,nnz,irn,jcn,tvals,rhs,mc29c,mc29r,keep,iwork,maxiw,work,maxw,cntl,icntl,info,rinfo)

    ! If factorization is successful, skip analysis on next call to MA41AD
    If(info(1) == 0 .and. info(8) <= maxw .and. info(7) <= maxiw) Then
      job_decmp = 2
      job_solve = 3
      Exit
    ElseIf(kdecomp == 5) Then
      Write(lun_diag,"(1x,a,i5,a,i5,a,i2)") 'Max iters: job=',job_decmp,', kdecomp=',kdecomp,', info(1)=',info(1)
      Stop
    Else
      Write(lun_diag,"(1x,a,i5,a,i5,a,i2)") 'Warning: job=',job_decmp,', kdecomp=',kdecomp,', info(1)=',info(1)

      ! Redo analysis step if first attempt at factorization failed
      job_decmp = 4

      If(info(1) == -5 .or. info(1) == -9 .or. info(1) >= 4) Then
        maxw = max(info(2),info(8))
        Deallocate(work)
        Allocate(work(maxw))
      ElseIf(info(8) > maxw) Then
        maxw = info(8)
        Deallocate(work)
        Allocate(work(maxw))
      EndIf

      If(info(1) == -7 .or. info(1) == -8) Then
        maxiw = max(info(2),info(7))
        Deallocate(iwork)
        Allocate(iwork(maxiw))
      ElseIf(info(7) > maxiw) Then
        maxiw = info(7)
        Deallocate(iwork)
        Allocate(iwork(maxiw))
      EndIf

    EndIf
  EndDo

! Stop timer
  stop_timer = xnet_wtime()
  timer_solve = timer_solve + stop_timer

  Return
End Subroutine jacobian_decomp                                                                       
  
Subroutine jacobian_bksub(yrhs,dy,t9rhs,dt9) 
!===============================================================================
! This routine performs back-substitution for a previously factored matrix and 
! the vector rhs.   
!===============================================================================
  Use controls
  Use jacobian_data
  Use timers
  Real(8), Intent(in)  :: yrhs(ny)
  Real(8), Intent(out) :: dy(ny)
  Real(8), Intent(in)  :: t9rhs
  Real(8), Intent(out) :: dt9
  Real(8) :: rhs(msize)
  Real(8) :: relerr(3)
  Integer :: kbksub,i
  
! Initiate timer
  start_timer = xnet_wtime()
  timer_solve = timer_solve - start_timer  

  rhs(1:ny)=yrhs
  If(iheat>0) rhs(ny+1)=t9rhs

! Perform back substitution 
  If(kmon(2) > kitmx) Then
    icntl(11) = 1 ! Previous NR iteration failed, so estimate error for possible recalculation of data structures
  Else
    icntl(11) = 0 ! Do not estimate error
  EndIf

! Perform back substitution 
  Do kbksub=1,5
    info = 0
    rinfo = 0.0
    Call MA41AD(job_solve,msize,nnz,irn,jcn,tvals,rhs,mc29c,mc29r,keep,iwork,maxiw,work,maxw,cntl,icntl,info,rinfo)
    If(info(1) == 0 .and. info(8) <= maxw .and. info(7) <= maxiw) Then
      dy = rhs(1:ny)
      If(iheat>0) dt9=rhs(ny+1)
      Exit
    ElseIf(kbksub == 5) Then
      Write(lun_diag,"(1x,a,i5,a,i5,a,i2)") 'Max iters: job=',job_solve,', kbksub=',kbksub,', info(1)=',info(1)
      Stop
    Else
      Write(lun_diag,"(1x,a,i5,a,i5,a,i2)") 'Warning: job=',job_solve,', kbksub=',kbksub,', info(1)=',info(1)
      job_solve = 6 ! Redo analysis and factorization if first attempt at solve fails

      If(info(1) == -5 .or. info(1) == -9 .or. info(1) == -11 .or. info(1) == -12 .or. info(1) >= 4) Then
        maxw = max(info(2),info(8))
        Deallocate(work)
        Allocate(work(maxw))
      ElseIf(info(8) > maxw) Then
        maxw = info(8)
        Deallocate(work)
        Allocate(work(maxw))
      EndIf

      If(info(1) == -7 .or. info(1) == -8) Then
        maxiw = max(info(2),info(7))
        Deallocate(iwork)
        Allocate(iwork(maxiw))
      ElseIf(info(7) > maxiw) Then
        maxiw = info(7)
        Deallocate(iwork)
        Allocate(iwork(maxiw))
      EndIf

    EndIf
  EndDo

! If the relative error becomes sufficiently large, reanalyze data structures in the next call to MA41AD
  If(icntl(11) > 0) Then
    relerr = rinfo(7:9)
    If( maxval(relerr)>maxerr ) Then
      Write(lun_diag,"(1x,a,3es12.5,a)") 'Warning: relerr=',(relerr(i),i=1,3),' > maxerr'
      job_solve = 6
      job_decmp = 4
    EndIf
  Else
    job_solve = 3
    job_decmp = 2
  EndIf
    
! Diagnostic output
  If(idiag>=4) Then
    Write(lun_diag,"(a)") 'BKSUB'
    Write(lun_diag,"(14es10.3)") dy
    If(iheat>0) Write(lun_diag,"(es10.3)") dt9
  EndIf

! Stop timer
  stop_timer = xnet_wtime()
  timer_solve = timer_solve + stop_timer

  Return
End Subroutine jacobian_bksub
!***************************************************************************************************
! net.f90 10/18/17
! This program is a driver to run XNet (on multiple processors if using MPI, by allocating successive
! zones to each processor).
!
! This driver reads in the controlling flags, the nuclear and reaction data. It also loops through
! reading the initial abundances and the thermodynamic trajectory before calling full_net for each
! zone.
!
! If you wish to use full_net in concert with a hydrodynmics code, you will need to supply these
! services from within the hydro.
!***************************************************************************************************

Program net
  !-------------------------------------------------------------------------------------------------
  ! This is the driver for running XNet
  !-------------------------------------------------------------------------------------------------
  Use nuclear_data, Only: ny, aa, zz, nname, index_from_name, read_nuclear_data
!$ Use omp_lib
  Use parallel, Only: parallel_finalize, parallel_initialize, parallel_myproc, parallel_nprocs, &
    & parallel_IOProcessor
  Use reaction_data, Only: read_reaction_data
  Use xnet_abundances, Only: ystart, yo, y, yt, ydot
  Use xnet_conditions, Only: t, tt, to, tdel, tdel_next, tdel_old, t9t, rhot, yet, t9, rho, ye, &
    & t9o, rhoo, yeo, t9dot, cv, etae, detaedt9, nt, ntt, nto, ints, intso, nstart, tstart, tstop, &
    & tdelstart, t9start, rhostart, yestart, nh, th, t9h, rhoh, yeh, nhmx, t9rhofind
  Use xnet_controls, Only: descript, iconvc, idiag, iheat, inucout, iprocess, iscrn, isolv, &
    & itsout, iweak0, nnucout, nnucout_string, output_nuc, szone, nzone, zone_id, changemx, tolm, tolc, &
    & yacc, ymin, tdel_maxmult, kstmx, kitmx, ev_file_base, bin_file_base, thermo_file, inab_file, &
    & lun_diag, lun_ev, lun_stdout, lun_ts, mythread, nthread, nzbatchmx, nzbatch, szbatch, lzactive, &
    & myid, nproc, read_controls
  Use xnet_eos, Only: eos_initialize
  Use xnet_evolve, Only: full_net
  Use xnet_flux, Only: flx_int, ifl_orig, ifl_term, flux_init
  Use xnet_integrate_bdf, Only: bdf_init
  Use xnet_jacobian, Only: read_jacobian_data
  Use xnet_match, Only: mflx, nflx, read_match_data
  Use xnet_nse, Only: nse_initialize
  Use xnet_preprocess, Only: net_preprocess
  Use xnet_screening, Only: screening_init
  Use xnet_timers, Only: xnet_wtime, start_timer, stop_timer, timer_setup
  Use xnet_types, Only: dp
  Use xnet_util, Only: name_ordered
  Use model_input_ascii
  Implicit None

  ! Local variables
  Integer :: i, k, izone ! Loop indices
  Integer :: ierr, inuc
  Integer :: ibatch, batch_count, izb

  ! Thermodynamic input data
  Real(dp), Allocatable :: dyf(:), flx_diff(:)

  ! Input Data descriptions
  Character(80) :: data_desc, data_dir
  Character(80), Allocatable :: abund_desc(:), thermo_desc(:)

  ! Filenames
  Character(80) :: ev_file, bin_file, diag_file
  Character(80) :: diag_file_base = 'net_diag'
  Character(25) :: ev_header_format

  ! Identify number of MPI nodes and ID number for this PE
  Call parallel_initialize()
  myid = parallel_myproc()
  nproc = parallel_nprocs()

  ! Identify threads
  !$omp parallel default(shared)
  mythread = 1
  !$ mythread = omp_get_thread_num()
  !$omp single
  nthread = 1
  !$ nthread = omp_get_num_threads()
  !$omp end single
  !$omp end parallel

  start_timer = xnet_wtime()
  timer_setup = timer_setup - start_timer

  ! Read and distribute user-defined controls
  Call read_controls(data_dir)

  ! If requested, pre-process the nuclear and reaction data.
  IF ( iprocess > 0 .and. parallel_IOProcessor() ) CALL net_preprocess( lun_stdout, data_dir, data_dir )

  !-------------------------------------------------------------------------------------------------
  ! Output files:
  ! The diagnostic output is per thread
  ! General output is per zone
  !-------------------------------------------------------------------------------------------------

  ! Open diagnositic output file, per thread if OMP
  !$omp parallel default(shared) private(diag_file)
  If ( idiag >= 0 ) Then
    diag_file = trim(diag_file_base)
    Call name_ordered(diag_file,myid,nproc)
    Call name_ordered(diag_file,mythread,nthread)
    Open(newunit=lun_diag, file=diag_file)
    Write(lun_diag,"(a5,2i5)") 'MyId',myid,nproc
    !$ Write(lun_diag,"(a,i4,a,i4)") 'Thread ',mythread,' of ',nthread
  EndIf
  !$omp end parallel

  ! Read and distribute nuclear and reaction data
  Call read_nuclear_data(data_dir,data_desc)
  Call read_reaction_data(data_dir)
  If ( idiag >= 0 ) Write(lun_diag,"(a)") (descript(i),i=1,3),data_desc

  ! Read and distribute jacobian matrix data
  Call read_jacobian_data(data_dir)

  ! Read data on matching forward and reverse reactions
  Call read_match_data(data_dir)

  ! Initialize screening
  Call screening_init

  ! Initialize flux tracking
  Call flux_init

  ! Initialize EoS for screening or self-heating
  Call eos_initialize

  If ( isolv == 3 ) Call bdf_init

  ! Convert output_nuc names into indices
  Do i = 1, nnucout
    Call index_from_name(output_nuc(i),inuc)
    If ( inuc < 1 .or. inuc > ny ) Then
      Write(lun_stdout,*) 'Output Nuc:',i,output_nuc(i),' not found'
      inucout(i) = ny
    Else
      inucout(i) = inuc
    EndIf
  EndDo

  ! Initialize NSE
  Call nse_initialize

  ! This is essentially a ceiling function for integer division
  batch_count = (nzone + nzbatchmx - 1) / nzbatchmx

  stop_timer = xnet_wtime()
  timer_setup = timer_setup + stop_timer

  !$omp parallel default(shared) &
  !$omp   private(dyf,flx_diff,abund_desc,thermo_desc,ev_file,bin_file,izone,ierr,ibatch,izb) &
  !$omp   copyin(timer_setup)

  start_timer = xnet_wtime()
  timer_setup = timer_setup - start_timer

  ! Set sizes of abundance arrays
  Allocate (y(ny,nzbatchmx),yo(ny,nzbatchmx),yt(ny,nzbatchmx),ydot(ny,nzbatchmx),ystart(ny,nzbatchmx))
  Allocate (dyf(0:ny),flx_diff(ny))

  ! Allocate conditions arrays
  Allocate (t(nzbatchmx),tt(nzbatchmx),to(nzbatchmx), &
    &       tdel(nzbatchmx),tdel_next(nzbatchmx),tdel_old(nzbatchmx), &
    &       t9(nzbatchmx),t9t(nzbatchmx),t9o(nzbatchmx), &
    &       rho(nzbatchmx),rhot(nzbatchmx),rhoo(nzbatchmx), &
    &       ye(nzbatchmx),yet(nzbatchmx),yeo(nzbatchmx), &
    &       nt(nzbatchmx),ntt(nzbatchmx),nto(nzbatchmx), &
    &       ints(nzbatchmx),intso(nzbatchmx), &
    &       t9dot(nzbatchmx),cv(nzbatchmx),etae(nzbatchmx),detaedt9(nzbatchmx))

  ! Allocate thermo history arrays
  Allocate (nh(nzbatchmx),nstart(nzbatchmx), &
    &       tstart(nzbatchmx),tstop(nzbatchmx),tdelstart(nzbatchmx), &
    &       t9start(nzbatchmx),rhostart(nzbatchmx),yestart(nzbatchmx), &
    &       th(nhmx,nzbatchmx),t9h(nhmx,nzbatchmx),rhoh(nhmx,nzbatchmx),yeh(nhmx,nzbatchmx))

  ! Allocate zone description arrays
  Allocate (abund_desc(nzbatchmx),thermo_desc(nzbatchmx))

  stop_timer = xnet_wtime()
  timer_setup = timer_setup + stop_timer

  ! Loop over zones in batches, assigning each batch of zones to MPI tasks in order
  !$omp do
  Do ibatch = myid+1, batch_count, nproc

    start_timer = xnet_wtime()
    timer_setup = timer_setup - start_timer

    ! Load the zone ID quadruplet
    zone_id(1) = ibatch ; zone_id(2) = 1 ; zone_id(3) = 1 ; zone_id(4) = 1

    ! Determine which zones are in this batch
    szbatch = szone + (ibatch-1)*nzbatchmx
    nzbatch = min(nzone-szbatch+1, nzbatchmx)

    ! Active zone mask
    Do izb = 1, nzbatchmx
      If ( izb <= nzbatch ) Then
        lzactive(izb) = .true.
      Else
        lzactive(izb) = .false.
      EndIf
    EndDo

    ! Read thermodynamic history files
    Call read_thermo_file(thermo_file,thermo_desc,ierr)

    ! Determine thermodynamic conditions at tstart
    Call t9rhofind(0,tstart,nstart,t9start,rhostart)

    ! Determine initial abundances
    Call load_initial_abundances(inab_file,abund_desc,ierr)

    ! Load initial abundances, time and timestep
    tdel(:) = 0.0
    nt(:)   = nstart(:)
    t(:)    = tstart(:)
    y(:,:)  = ystart(:,:)
    t9(:)   = t9start(:)
    rho(:)  = rhostart(:)
    ye(:)   = yestart(:)

    ! Open the evolution file
    If ( itsout >= 2 ) Then
      Do izb = 1, nzbatch
        izone = izb + szbatch - 1
        ev_file = trim(ev_file_base)
        Call name_ordered(ev_file,izone,nzone)
        If ( idiag >= 0 ) Write(lun_diag,"(a,i5,7es10.3)") trim(ev_file), &
          & nh(izb),th(nh(izb),izb),t9h(nh(izb),izb),rhoh(nh(izb),izb),tstart(izb),tstop(izb)
        Open(newunit=lun_ev(izb), file=ev_file)

        ! Write evolution file header
        Write(ev_header_format,"(a)") "(a4,a15,4a10,"//trim(nnucout_string)//"a9,a4)"
        Write(lun_ev(izb),ev_header_format) &
          & 'k ',' Time ',' T(GK) ',' Density ',' dE/dt ',' Timestep ',(nname(inucout(i)),i=1,nnucout), ' It '
      EndDo
    EndIf

    ! Open the binary time series file
    If ( itsout >= 1 ) Then
      Do izb = 1, nzbatch
        izone = izb + szbatch - 1
        bin_file = trim(bin_file_base)
        Call name_ordered(bin_file,izone,nzone)
        Open(newunit=lun_ts(izb), file=bin_file, form='unformatted')

        ! Write Control Parameters to ts file
        Write(lun_ts(izb)) (descript(i),i=1,3),data_desc
        Write(lun_ts(izb)) kstmx,kitmx,iweak0,iscrn,iconvc,changemx,tolm,tolc,yacc,ymin,tdel_maxmult,iheat,isolv

        ! Write abundance description to ts file
        Write(lun_ts(izb)) inab_file(izone),abund_desc(izb)

        ! Write thermo description to ts file
        Write(lun_ts(izb)) thermo_file(izone),thermo_desc(izb)

        ! Write species identifiers to ts file
        Write(lun_ts(izb)) ny,zz,aa

        ! Write flux identifiers to ts file
        Write(lun_ts(izb)) mflx,ifl_orig,ifl_term
      EndDo
    EndIf

    stop_timer = xnet_wtime()
    timer_setup = timer_setup + stop_timer

    ! Evolve abundance from tstart to tstop
    Call full_net

    ! Test how well sums of fluxes match abundances changes
    Do izb = 1, nzbatch
      If ( idiag >= 3 ) Then
        dyf = 0.0
        Do k = 1, mflx
          dyf(nflx(1:4,k)) = dyf(nflx(1:4,k)) + flx_int(k,izb)
          dyf(nflx(5:8,k)) = dyf(nflx(5:8,k)) - flx_int(k,izb)
        EndDo
        flx_diff(:) = y(:,izb) - ystart(:,izb) + dyf(1:ny)
        Write(lun_diag,"(a,es11.3)") 'Compare Integrated flux to abundance change',dyf(0)
        Write(lun_diag,"(a)") 'Species Flux Sum + Y Final - Y Initial = Flux Diff'
        Write(lun_diag,"(a5,4es11.3)") (nname(k),dyf(k),y(k,izb),ystart(k,izb),flx_diff(k),k=1,ny)
      EndIf

      ! Close zone output files
      If (itsout >= 2 ) Close(lun_ev(izb))
      If (itsout >= 1 ) Close(lun_ts(izb))
    EndDo
  EndDo
  !$omp end do

  ! Close diagnostic output file
  If ( idiag >= 0 ) Close(lun_diag)
  !$omp end parallel

  ! Wait for all nodes to finish
  Call parallel_finalize()

End Program net



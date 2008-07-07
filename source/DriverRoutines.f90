!> \brief contains the routines that "drive" the program
!> \author Alin M Elena
!> \date 02/11/07, 18:04:08

module m_DriverRoutines
  use m_Constants
  use m_Useful
  use m_Types
  use m_TightBinding
  use m_Gutenberg
  use m_LinearAlgebra
  use m_SCF
  use m_Electrostatics
  use m_Hamiltonian
  use m_Dynamics
  use m_DensityMatrix
  use m_LBFGS
  use m_BFGS
  implicit none

  private

  public :: SinglePoint
  public :: BornOppenheimerDynamics
  public :: EhrenfestDynamics
  public :: EhrenfestDynamicsDamped
  public :: Geometry
  contains

!> \brief the driver for total energy and electronic structure calculations
!> \author Alin M Elena
!> \date 02/11/07, 18:03:43
!> \param ioLoc type(ioType) contains all the info about I/O files
!> \param genLoc type(generalType) contains the info needed by the program to k_run
!> \param atomic type(atomicxType) contains all info about the atoms and basis set and some parameters
!> \param tbMod type(modelType) contains information about the tight binding model parameters
!> \param sol type(solutionType) contains information about the solution space
  subroutine SinglePoint(ioLoc,genLoc,atomic,tbMod,sol)
    character(len=*), parameter :: sMyName="SinglePoint"
    type(ioType), intent(inout) :: ioLoc
    type(generalType), intent(inout) :: genLoc
    type(atomicxType), intent(inout) :: atomic
    type(modelType), intent(inout) :: tbMod
    type(solutionType), intent(inout) :: sol
    real(k_pr) :: eenergy,renergy, minusts,scfE
    integer :: aux,xyz

    eenergy=0.0_k_pr
    renergy=0.0_k_pr
    scfE=0.0_k_pr
    if (genLoc%spin)  then
      call InitMagneticMoment(atomic)
      write(ioLoc%uout,"(a)")"Initial Magnetic Moment"
      call PrintMagneticMoment(atomic,sol,.false.,ioLoc)
    endif
    call FullSCF(ioLoc,genLoc,atomic,tbMod,sol)
    eenergy = ElectronicEnergy(genLoc,sol,ioLoc)
    renergy = RepulsiveEnergy(genLoc,atomic%atoms,tbMod)
    minusts = sol%electronicEntropy
    write(ioLoc%uout,'(/a)')&
         "--Single Point Run----------------------------------------------"
    call PrintAtoms(ioLoc,genLoc,atomic)
    call PrintCharges(genLoc,atomic,ioLoc)
    call PrintDipoles(atomic,ioLoc)
    if (genLoc%spin) call PrintMagneticMoment(atomic,sol,.false.,ioLoc)
    write(ioLoc%uout,"(/a,f16.8,/a,f16.8)")&
          "Electronic energy = ",eenergy, &
       "Repulsive energy  = ",renergy
    if (genLoc%scf) then
!  make it to print more information
      aux=ioLoc%verbosity
      ioLoc%verbosity=k_HighVerbos
      scfE = ScfEnergy(genLoc,atomic,sol,tbMod,ioLoc)
      ioLoc%verbosity=aux
    else
      scfE = 0.0_k_pr
    endif
    write(ioLoc%uout,"(a,f16.8,/a,f16.8,/a,f16.8,/a,f16.8)") &
       "Total SCF energy  = ",scfE, &
          "-TS               = ",minusts, &
          "Total energy      = ",eenergy+renergy+scfE+minusts,&
          "# of electrons    = ", real(MatrixTrace(sol%rho,ioLoc))
    call PrintForces(atomic%atoms,ioLoc)
    write(ioLoc%uout,'(/a/)')&
          "_______________________________________________________________"

   sol%totalEnergy=eenergy+renergy+minusts+scfE
   xyz=GetUnit()
   open(xyz,file="coords.mxz",status="unknown",action="write")
   call PrintXYZ(xyz,atomic,.false.,getUnits(genLoc))
   close(xyz)
  end subroutine SinglePoint

!> \brief driver routine for verlet velocity Born-Oppenheimer molecular dynamics
!> \author Alin M Elena
!> \date 10/11/07, 13:18:53
!> \param io type(ioType) contains all the info about I/O files
!> \param gen type(generalType) contains the info needed by the program to k_run
!> \param atomic type(atomicxType) contains all info about the atoms and basis set and some parameters
!> \param tb type(modelType) contains information about the tight binding model parameters
!> \param sol type(solutionType) contains information about the solution space
  subroutine BornOppenheimerDynamics(io,gen,atomic,tb,sol)
    character(len=*), parameter :: myname = "BornOppenheimerDynamics"
    type(ioType), intent(inout) :: io
    type(generalType), intent(inout) :: gen
    type(atomicxType), intent(inout) :: atomic
    type(solutionType), intent(inout) :: sol
    type(modelType), intent(inout) :: tb
    integer :: aniunit, eneunit,xunit,runit
    real(k_pr) :: eenergy,renergy,kenergy,penergy,scfE,minusts
    integer  :: i,istep,k
    real(k_pr) :: dt,mi
    character(len=k_ml) :: saux
    eneunit=GetUnit()
    xunit=GetUnit()
    runit=GetUnit()
    write(io%uout,'(/a/)')&
      '--Velocity Verlet Born-Oppenheimer Dynamics---------------------'

    if (gen%writeAnimation) then
!          open(unit=xunit,file="bo_dyn.gcd",form="UNFORMATTED",status="unknown",action="write")
!          call write_header(xunit,gen%nsteps,gen%deltat,atomic%natoms)
!          open(unit=runit,file="bo_dyn.rho",form="UNFORMATTED",status="unknown",action="write")
!          call write_header_rho(runit,gen%nsteps,gen%deltat,n)
      call PrintXYZ(io%uani,atomic,.false.,"T = 0.0")
    endif
    open(file='bo_dyn.ENE',unit=eneunit)
    ! initialize forces and velocities
    call SinglePoint(io,gen,atomic,tb,sol)
    call InitVelocities(gen,atomic,sol)
    dt = gen%deltat
    !write out the initial vels, forces and energies
    call PrintVelocities(io,atomic)
    call PrintForces(atomic%atoms,io)
    eenergy = ElectronicEnergy(gen,sol,io)
    renergy = RepulsiveEnergy(gen,atomic%atoms,tb)
    minusts = sol%electronicEntropy
    if (gen%scf) then
      scfE = ScfEnergy(gen,atomic,sol,tb,io)
    else
      scfE = 0.0_k_pr
    endif

    write(io%uout,'(/a,f13.6,/a,f13.6,/a,f13.6,/a,f25.18,/a,f25.18,/)')&
       'Electronic energy = ',eenergy, &
      'Repulsive energy  = ',renergy, &
      'SCF energy        = ',scfE, &
         '-TS               = ',minusts, &
         'Total energy      = ',eenergy+renergy+scfE+minusts
    sol%totalEnergy=eenergy+renergy+minusts+scfE
    ! this is the time loop
    write(eneunit,'(a1,a28,6a29)')"#","Time",  "Repulsive Energy ",  "Electronic Energy",  "SCF Energy",&
      "-TS","Kinetic Energy",  "Total Energy"
    do istep=1,gen%nsteps
      !set global time variable
      gen%CurrSimTime = istep*dt*k_time2SI
       ! calculates positions at t+dt
!       write(io%uout,*)"timestep"
!       call PrintCoordinates(io,atomic)
!       call PrintForces(atomic%atoms,io)
      do k=1,atomic%atoms%nmoving
        i=atomic%atoms%moving(k)
        mi = atomic%species%mass(atomic%atoms%sp(i))
        atomic%atoms%x(i) = atomic%atoms%x(i) &
          + dt * atomic%atoms%vx(i) &
          + 0.5_k_pr * dt*dt * atomic%atoms%fx(i) / mi
        atomic%atoms%y(i) = atomic%atoms%y(i) &
          + dt * atomic%atoms%vy(i) &
          + 0.5_k_pr * dt*dt * atomic%atoms%fy(i) / mi
        atomic%atoms%z(i) = atomic%atoms%z(i) &
          + dt * atomic%atoms%vz(i) &
          + 0.5_k_pr * dt*dt * atomic%atoms%fz(i) / mi
      enddo
!       call PrintVelocities(io,atomic)
!       call PrintCoordinates(io,atomic)
      ! store forces at t in fold
      do k=1,atomic%atoms%nmoving
        i=atomic%atoms%moving(k)
        atomic%atoms%fxo(i) = atomic%atoms%fx(i)
        atomic%atoms%fyo(i) = atomic%atoms%fy(i)
        atomic%atoms%fzo(i) = atomic%atoms%fz(i)
      enddo
      ! calculate forces at t+dt
      call SinglePoint(io,gen,atomic,tb,sol)
      ! calculate velocities at t+dt
      do k=1,atomic%atoms%nmoving
        i=atomic%atoms%moving(k)
        mi = atomic%species%mass(atomic%atoms%sp(i))
        atomic%atoms%vx(i) = atomic%atoms%vx(i) &
          + 0.5_k_pr * dt * (atomic%atoms%fx(i) + atomic%atoms%fxo(i)) / mi
        atomic%atoms%vy(i) = atomic%atoms%vy(i) &
          + 0.5_k_pr * dt * (atomic%atoms%fy(i) + atomic%atoms%fyo(i)) / mi
        atomic%atoms%vz(i) = atomic%atoms%vz(i) &
          + 0.5_k_pr * dt * (atomic%atoms%fz(i) + atomic%atoms%fzo(i)) / mi
      enddo
       ! scale velocities
      if (gen%scaleVelocities) then
        call ScaleVelocities(gen,atomic)
      endif
       ! now calculate the energies
      eenergy = ElectronicEnergy(gen,sol,io)
      renergy = RepulsiveEnergy(gen,atomic%atoms,tb)
      minusts = sol%electronicEntropy
      if (gen%scf) then
        scfE = ScfEnergy(gen,atomic,sol,tb,io)
      else
        scfE = 0.0_k_pr
      endif
      penergy = eenergy + renergy + scfE + minusts
      kenergy = KineticEnergy(atomic)
      if (gen%writeAnimation) then
        if (gen%writeAnimation) then
!             call BuildDensity(density)
!             call calc_charges(rho)
!             call calc_dipoles(density)
!             call write_frame(xunit)
!             call writeAnimation_frame(aniunit)
! !           call write_frame_rho(runit)
          write(saux,'(a,f0.8,a)')"Time = ",gen%CurrSimTime," fs"
          call PrintXYZ(io%uani,atomic,.false.,trim(saux))
        endif
      endif
      if (io%Verbosity >= k_HighVerbos) then
        call PrintCoordinates(io,atomic,gen)
        call PrintForces(atomic%atoms,io)
      endif
      write(io%uout,'(i5,a,f13.6,a,f13.6,a,f13.6)')&
            istep,' P = ',penergy,' K = ',kenergy,' E = ',penergy+kenergy
      write(eneunit,'(7f29.18)')gen%currSimTime,renergy,eenergy,scfE,minusts,kenergy,penergy+kenergy
    enddo

    if (gen%writeAnimation) then
!          close(xunit)
!          close(runit)
    endif
    close(eneunit)
    write(io%uout,'(/a)')&
       'Final coordinates:'
    call PrintCoordinates(io,atomic,gen)
    write(io%uout,'(/a/)')&
         '----------------------------------------------------------------'
   end subroutine BornOppenheimerDynamics

!> \brief driver routine for verlet velocity Ehrenfest molecular dynamics
!> \author Alin M Elena
!> \date 10/11/07, 15:22:53
!> \param io type(ioType) contains all the info about I/O files
!> \param gen type(generalType) contains the info needed by the program to k_run
!> \param atomic type(atomicxType) contains all info about the atoms and basis set and some parameters
!> \param tb type(modelType) contains information about the tight binding model parameters
!> \param sol type(solutionType) contains information about the solution space
!> \internal it aborts if the calculation is not scf
  subroutine EhrenfestDynamics(io,gen,atomic,tb,sol)
    character(len=*), parameter :: myname = 'EhrenfestDynamics'
    type(ioType), intent(inout) :: io
    type(generalType), intent(inout) :: gen
    type(atomicxType), intent(inout) :: atomic
    type(solutionType), intent(inout) :: sol
    type(modelType), intent(inout) :: tb
    integer :: aniunit, eneunit, popunit, xunit,runit, accUnit, donUnit, spacUnit
    real(k_pr) :: eenergy,renergy,kenergy,penergy,scfE
    integer  :: i,istep,k
    real(k_pr) :: dt,mi
    complex(k_pr) :: ihbar,trrho,st
    type(matrixType) :: rhoold,rhodot,rhonew,rho0
    real(k_pr) ::biasFactor,bfa
    character(len=k_ml) :: saux


    eneunit=GetUnit()
    popunit=GetUnit()
    xunit=GetUnit()
    runit=GetUnit()
    accUnit=GetUnit()
    donUnit=GetUnit()
    spacUnit=GetUnit()
    write(io%uout,'(/a/)')&
         '--Velocity Verlet Ehrenfest Dynamics----------------------------'
    if (gen%writeAnimation) then
      open(unit=xunit,file="eh_dyn.gcd",form="UNFORMATTED",status="unknown",action="write")
      open(unit=accUnit,file="eacceptor.dat",status="unknown",action="write")
      open(unit=donUnit,file="edonor.dat",status="unknown",action="write")
      open(unit=spacUnit,file="espacer.dat",status="unknown",action="write")
!      call write_header(xunit,gen%nsteps,gen%deltat,atomic%natoms)
      open(unit=runit,file="eh_dyn.rho",form="UNFORMATTED",status="unknown",action="write")
    endif
    open(file='eh_dyn.ENE',unit=eneunit)
    open(file='eh_dyn.POP',unit=popunit)
    ! prepare the electronic subsystem,
    ! which is an eigenstate of the hamitonian
    ! with the bias
    call FullSCF(io,gen,atomic,tb,sol)
    dt = gen%deltat
    ! initialize DM storage spaces
    call CreateMatrix(rhoold,sol%h%dim,.true.)
    call CreateMatrix(rhodot,sol%h%dim,.true.)
    call CreateMatrix(rhonew,sol%h%dim,.true.)
    call CreateMatrix(rho0,sol%h%dim,.true.)

    if (gen%writeAnimation) then
      call BuildDensity(atomic,sol)
      call CalcExcessCharges(gen,atomic,sol)
      call CalcDipoles(gen,atomic,sol,tb)
      call PrintXYZ(io%uani,atomic,.false.,"T=0.0")
      write(accUnit,*) "0.0", ChargeOnGroup(atomic%atoms%acceptor,atomic%atoms)
      write(donUnit,*) "0.0", ChargeOnGroup(atomic%atoms%donor,atomic%atoms)
      write(spacUnit,*) "0.0", ChargeOnGroup(atomic%atoms%spacer,atomic%atoms)
    endif

    ! now build a hamiltonian with no bias
    call BuildHamiltonian(io,gen,atomic,tb,sol)
    call CopyMatrix(rho0,sol%rho,io)
    if (gen%BiasRampSteps>0) then
      call AddBias(1.0_k_pr,atomic,sol)
    endif
    call CopyMatrix(sol%hin,sol%h,io)
    call BuildDensity(atomic,sol)
    if((.not.gen%compElec).and.(gen%electrostatics==k_electrostaticsMultipoles)) then
      call initQvs(atomic,gen,sol,tb,sol%density)
    endif
!          if (.not.gen%comp_elec) then
!             if (gen%electrostatics==tbu_multi) call init_qvs(density)
!          endif
    call AddH2(gen,atomic,sol,tb,io)
    ihbar = cmplx(0.0_k_pr,-1.0_k_pr/k_hbar,k_pr)
    ! go back in time one step for the DM integration
    call Commutator(rhodot,sol%h,sol%rho,io)
    st = cmplx(-dt,0.0_k_pr,k_pr)
    call ScalarTMatrix(ihbar*st,rhodot,io)
    call MatrixCeaApbB(rhoold,sol%rho,rhodot,k_cone,k_cone,io)
      ! calculate the forces from the prepared DM and the present H
    call CopyMatrix(sol%h,sol%hin,io)
    call ZeroForces(atomic)
    call RepulsiveForces(gen,atomic%atoms,tb)
    call electronicForces(atomic,gen,tb,sol,io)
    ! initialize the velocities
    call InitVelocities(gen,atomic,sol)
    ! now we are ready to start the dynamics,
    ! we have the forces, velocities, positions
    ! and rho at time t
    write(eneunit,'(a1,a24,6a25)')"#","Time",  "Repuilsive Energy ",  "Electronic Energy",  "SCF Energy",&
      "Kinetic Energy",  "Total Energy",  "No of Electrons"
    st = cmplx(2.0_k_pr*dt,0.0_k_pr,k_pr)
    do istep=1,gen%nsteps
   !set global time variable
      gen%CurrSimTime = istep*dt*k_time2SI
      call BuildDensity(atomic,sol)
      if((.not.gen%compElec).and.(gen%electrostatics==k_electrostaticsMultipoles)) then
        call initQvs(atomic,gen,sol,tb,sol%density)
      endif
!             if (.not.gen%comp_elec) then
!                if (gen%electrostatics==tbu_multi) call init_qvs(density)
!             endif
      call AddH2(gen,atomic,sol,tb,io)

      call ZeroMatrix(rhodot,io)
      call Commutator(rhodot,sol%h,sol%rho,io)
      call ScalarTMatrix(ihbar*st,rhodot,io)
      call MatrixCeaApbB(rhonew,rhoold,rhodot,k_cone,k_cone,io)
       ! at this point rho contains the rho at time=t
       ! propagate the positions
       ! calculates positions at t+dt
      do k=1,atomic%atoms%nmoving
        i=atomic%atoms%moving(k)
        mi = atomic%species%mass(atomic%atoms%sp(i))
        atomic%atoms%x(i) = atomic%atoms%x(i) &
         + dt * atomic%atoms%vx(i) &
         + 0.5_k_pr * dt*dt * atomic%atoms%fx(i) / mi
        atomic%atoms%y(i) = atomic%atoms%y(i) &
         + dt * atomic%atoms%vy(i) &
         + 0.5_k_pr * dt*dt * atomic%atoms%fy(i) / mi
        atomic%atoms%z(i) = atomic%atoms%z(i) &
         + dt * atomic%atoms%vz(i) &
         + 0.5_k_pr * dt*dt * atomic%atoms%fz(i) / mi
      enddo
       ! store forces at t in fold
      do k=1,atomic%atoms%nmoving
        i=atomic%atoms%moving(k)
        atomic%atoms%fxo(i) = atomic%atoms%fx(i)
        atomic%atoms%fyo(i) = atomic%atoms%fy(i)
        atomic%atoms%fzo(i) = atomic%atoms%fz(i)
      enddo
       ! shuffle the DMs, rho is now rho(t+dt)
      call CopyMatrix(rhoold,sol%rho,io)
      call CopyMatrix(sol%rho,rhonew,io)
           ! calculate forces at t+dt
      call BuildHamiltonian(io,gen,atomic,tb,sol)
       ! Ramp for the bias
      if ((gen%BiasRampSteps>0).and.((istep)<=gen%BiasRampSteps)) then
        bfa = real(istep,k_pr)/real(gen%BiasRampSteps,k_pr)
        biasFactor = -(bfa-1)**3 * (1 + 3*bfa + 6*bfa**2)
        call AddBias(biasFactor,atomic,sol)
      endif

      call BuildDensity(atomic,sol)
      if((.not.gen%compElec).and.(gen%electrostatics==k_electrostaticsMultipoles)) then
        call initQvs(atomic,gen,sol,tb,sol%density)
      endif
!             if (.not.gen%comp_elec) then
!                if (gen%electrostatics==tbu_multi) call init_qvs(density)
!             endif

      call ZeroForces(atomic)
      call RepulsiveForces(gen,atomic%atoms,tb)
      call electronicForces(atomic,gen,tb,sol,io)
      call ScfForces(gen,atomic,sol,tb,io)
       ! calculate velocities at t+dt
      do k=1,atomic%atoms%nmoving
        i=atomic%atoms%moving(k)
        mi = atomic%species%mass(atomic%atoms%sp(i))
        atomic%atoms%vx(i) = atomic%atoms%vx(i) &
         + 0.5_k_pr * dt * (atomic%atoms%fx(i) + atomic%atoms%fxo(i)) / mi
        atomic%atoms%vy(i) = atomic%atoms%vy(i) &
         + 0.5_k_pr * dt * (atomic%atoms%fy(i) + atomic%atoms%fyo(i)) / mi
        atomic%atoms%vz(i) = atomic%atoms%vz(i) &
         + 0.5_k_pr * dt * (atomic%atoms%fz(i) + atomic%atoms%fzo(i)) / mi

      enddo

       ! scale velocities
      if (gen%scaleVelocities) then
        call ScaleVelocities(gen,atomic)
      endif
      if (gen%spin) then
        trrho   = MatrixTrace(sol%rho,io)
      else
        trrho   = 2.0_k_pr * MatrixTrace(sol%rho,io)
      endif
      eenergy = ElectronicEnergy(gen,sol,io)
      renergy = RepulsiveEnergy(gen,atomic%atoms,tb)
      if (gen%scf) then
        scfE = ScfEnergy(gen,atomic,sol,tb,io)
      else
        scfE = 0.0_k_pr
      endif

      penergy = eenergy + renergy + scfE
      kenergy = KineticEnergy(atomic)

      if (gen%writeAnimation) then
        if (gen%writeAnimation) then
          call CalcExcessCharges(gen,atomic,sol)
          call CalcDipoles(gen,atomic,sol,tb)
  !               call writeAnimation_frame(aniunit)
  !               call write_frame(xunit)
  !               call write_frame_rho(runit,rho0)
          write(accUnit,*) gen%CurrSimTime, ChargeOnGroup(atomic%atoms%acceptor,atomic%atoms)
          write(donUnit,*) gen%CurrSimTime, ChargeOnGroup(atomic%atoms%donor,atomic%atoms)
          write(spacUnit,*) gen%CurrSimTime, ChargeOnGroup(atomic%atoms%spacer,atomic%atoms)
          write(saux,'(a,f0.8)')"Time = ", gen%CurrSimTime
          call PrintXYZ(io%uani,atomic,.false.,trim(saux))
        endif
      endif
!            call write_currents(h,rho)
!            if (mod(istep,50).eq.1) call write_rho_eigenvalues(rho)
      write(eneunit,'(7f25.18)')gen%CurrSimTime,renergy,eenergy,scfE,kenergy,penergy+kenergy,real(trrho)

    enddo !istep loop
    if (gen%writeAnimation) then
      close(xunit)
      close(runit)
      close(accUnit)
      close(donUnit)
      close(spacUnit)
    endif
    close(eneunit)
    close(popunit)
    call DestroyMatrix(rhoold,io)
    call DestroyMatrix(rhodot,io)
    call DestroyMatrix(rhonew,io)
    call DestroyMatrix(rho0,io)

    write(io%uout,'(/a/)')&
      'End Velocity Verlet-------------------------------------------------------------'
  end subroutine EhrenfestDynamics
!> \brief driver routine for verlet velocity Ehrenfest molecular dynamics
!> damped
!> \details numerical instabilities in time propragation of density matrix are handled using the scheme proposed in
!> J. Phys.: Condens. Matter Vol 17, Issue 25 (2005), pp. 3985-3995, section 3.3
!> \author Alin M Elena
!> \date 10/11/07, 15:22:53
!> \param io type(ioType) contains all the info about I/O files
!> \param gen type(generalType) contains the info needed by the program to k_run
!> \param atomic type(atomicxType) contains all info about the atoms and basis set and some parameters
!> \param tb type(modelType) contains information about the tight binding model parameters
!> \param sol type(solutionType) contains information about the solution space
  subroutine EhrenfestDynamicsDamped(io,gen,atomic,tb,sol)
    character(len=*), parameter :: myname = 'EhrenfestDynamicsDamped'
    type(ioType), intent(inout) :: io
    type(generalType), intent(inout) :: gen
    type(atomicxType), intent(inout) :: atomic
    type(solutionType), intent(inout) :: sol
    type(modelType), intent(inout) :: tb
    integer :: dipunit, eneunit, popunit, xunit,runit, accUnit, donUnit, spacUnit,bchUnit,ochUnit
    real(k_pr) :: eenergy,renergy,kenergy,penergy,scfE
    integer  :: i,istep,k,j
    real(k_pr) :: dt,mi,inpn
    complex(k_pr) :: ihbar,trrho,st
    real(k_pr) ::biasFactor,bfa,gamma,ts
    character(len=k_ml) :: saux
    integer :: l,m
    logical :: OrbitalCurrent
    integer,allocatable :: currUnit(:)

    if (atomic%atoms%ncurrentOnBonds<=0) then
      OrbitalCurrent=.false.
    else
      OrbitalCurrent=.true.
      allocate (currUnit(1:atomic%atoms%ncurrentOnBOnds))
    endif
    eneunit=GetUnit()
    xunit=GetUnit()
    runit=GetUnit()
    accUnit=GetUnit()
    donUnit=GetUnit()
    spacUnit=GetUnit()
    bchUnit=GetUnit()
    if (OrbitalCurrent) then
      do i=1,atomic%atoms%ncurrentOnBOnds
        currUnit(i)=GetUnit()
      enddo
    endif

    write(io%uout,'(/a/)')&
         '--Velocity Verlet Ehrenfest Dynamics Damped----------------------------'
    gamma=-gen%Gamma

    if (gen%writeAnimation) then
      open(unit=xunit,file="eh_dyn.gcd",form="UNFORMATTED",status="replace",action="write")
      open(unit=accUnit,file="eacceptor.dat",status="replace",action="write")
      open(unit=donUnit,file="edonor.dat",status="replace",action="write")
      open(unit=spacUnit,file="espacer.dat",status="replace",action="write")
      open(unit=bchUnit,file="bondCharges.cxz",status="replace",action="write")
      if (OrbitalCurrent) then
        do i=1,atomic%atoms%ncurrentOnBonds
          write(saux,'(a,2i0,a)')"bondChargesOrbital",atomic%atoms%currentOnBonds(2*i-1),atomic%atoms%currentOnBonds(2*i),".cxz"
          open(unit=currUnit(i),file=trim(saux),status="replace",action="write")
        enddo
      endif
      open(unit=runit,file="eh_dyn.rho",form="UNFORMATTED",status="replace",action="write")
    endif
    open(file='eh_dyn.ENE',unit=eneunit)
    ! prepare the electronic subsystem,
    ! which is an eigenstate of the hamitonian
    ! with the bias
    i=io%Verbosity
    io%Verbosity=k_highVerbos+1
    gen%lIsExcited=.false.
    call SinglePoint(io,gen,atomic,tb,sol)
    atomic%atoms%chrg0=atomic%atoms%chrg
    dt = gen%deltat
    ! initialize DM storage spaces
    call CopyMatrix(sol%rho0,sol%rho,io)

    select case(gen%wdensity)
    case(k_wrSCF)
      gen%lIsExcited=.true.
      call SinglePoint(io,gen,atomic,tb,sol)
      gen%lIsExcited=.false.
    case(k_wrnSCF)
      call CreateDensityMatrixExcited(gen,atomic,sol,io)
      gen%lIsExcited=.false.
    case(k_wrTailored)
      gen%lIsExcited=.true.
      call SinglePoint(io,gen,atomic,tb,sol)
      gen%lIsExcited=.false.
      do i=1, sol%rho%dim-1
        do j=i+1,sol%rho%dim
          sol%rho%a(i,j)=cmplx(0.0_k_pr,0.0_k_pr,k_pr)
          sol%rho%a(j,i)=cmplx(0.0_k_pr,0.0_k_pr,k_pr)
        enddo
      enddo
!       call GetRho(sol%rho)
!       gen%lIsExcited=.false.
   end select
   io%Verbosity=i
   write(io%uout,'(/a/)')&
         '--Setup ended----------------------------'

    if((.not.gen%compElec).and.(gen%electrostatics==k_electrostaticsMultipoles)) then
      call initQvs(atomic,gen,sol,tb,sol%density)
    endif
!          if (.not.gen%comp_elec) then
!             if (gen%electrostatics==tbu_multi) call init_qvs(density)
!          endif
    ! now build a hamiltonian with no bias
    call BuildHamiltonian(io,gen,atomic,tb,sol)
    call MatrixCeaApbB(sol%deltaRho,sol%rho,sol%rho0,k_cone,-k_cone,io)
    if (gen%BiasRampSteps>0) then
      call AddBias(1.0_k_pr,atomic,sol)
    endif
    call CopyMatrix(sol%hin,sol%h,io)
    call BuildDensity(atomic,sol)
    if (gen%scf) then
      call AddH2(gen,atomic,sol,tb,io)
    endif

    ihbar = cmplx(0.0_k_pr,-1.0_k_pr/k_hbar,k_pr)
    ! go back in time one step for the DM integration
    call Commutator(sol%rhodot,sol%h,sol%rho,io)
    st = cmplx(-dt,0.0_k_pr,k_pr)
    call ScalarTMatrix(ihbar*st,sol%rhodot,io)
    call ScalarTMatrix(gamma*st,sol%deltaRho,io)
!! get rid of the diagonal terms of rho
    call ZeroDiagonalMatrix(sol%deltaRho,io)
    call MatrixCeaApbB(sol%rhoold,sol%rho,sol%rhodot,k_cone,k_cone,io)
    call MatrixCeaApbB(sol%rhoold,sol%rhoold,sol%deltaRho,k_cone,k_cone,io)
      ! calculate the forces from the prepared DM and the present H
    call CopyMatrix(sol%h,sol%hin,io)
    call ZeroForces(atomic)
    call RepulsiveForces(gen,atomic%atoms,tb)
    call electronicForces(atomic,gen,tb,sol,io)

    ! initialize the velocities
    call InitVelocities(gen,atomic,sol)
    ! now we are ready to start the dynamics,
    ! we have the forces, velocities, positions
    ! and rho at time t
    st = cmplx(2.0_k_pr*dt,0.0_k_pr,k_pr)
    gen%CurrSimTime=0.0_k_pr
    if (gen%writeAnimation) then

      if (gen%spin) then
        trrho   = MatrixTrace(sol%rho,io)
      else
        trrho   = 2.0_k_pr * MatrixTrace(sol%rho,io)
      endif
      eenergy = ElectronicEnergy(gen,sol,io)
      renergy = RepulsiveEnergy(gen,atomic%atoms,tb)
      if (gen%scf) then
        scfE = ScfEnergy(gen,atomic,sol,tb,io)
      else
        scfE = 0.0_k_pr
      endif
      penergy = eenergy + renergy + scfE
      kenergy = KineticEnergy(atomic)
      write(eneunit,'(a1,a24,6a25)')"#","Time",  "Repuilsive Energy ",  "Electronic Energy",  "SCF Energy",&
      "Kinetic Energy",  "Total Energy",  "No of Electrons"
      write(eneunit,'(7f25.18)')gen%CurrSimTime,renergy,eenergy,scfE,kenergy,penergy+kenergy,real(trrho)
      call CalcExcessCharges(gen,atomic,sol)
      call CalcDipoles(gen,atomic,sol,tb)
!       write(accUnit,*) "0.0", ChargeOnGroup(atomic%atoms%acceptor,atomic%atoms)
!       write(donUnit,*) "0.0", ChargeOnGroup(atomic%atoms%donor,atomic%atoms)
!       write(spacUnit,*) "0.0", ChargeOnGroup(atomic%atoms%spacer,atomic%atoms)
      call PrintXYZ(io%uani,atomic,.false.,"T = 0.0 fs")
      if (gen%scf) then
        call AddH2(gen,atomic,sol,tb,io)
      endif
      call ComputeBondCurrents(gen,atomic,sol,io,OrbitalCurrent)
      call PrintBondCurrents(bchUnit,atomic,sol,"T= 0.0 fs",1.0_k_pr)
      if (OrbitalCurrent) then
        do i=1,atomic%atoms%ncurrentOnBOnds
          call ComputeBondCurrentsOnOrbitals(gen,atomic,sol,io,atomic%atoms%currentOnBonds(2*i-1),atomic%atoms%currentOnBonds(2*i))
          call PrintBondCurrents(currUnit(i),atomic,sol,"T= 0.0 fs",1.0_k_pr)
        enddo
      endif
    endif

   call CopyMatrix(sol%h,sol%hin,io)

    do istep=1,gen%nsteps
   !set global time variable
      gen%CurrSimTime = (istep+1)*dt*k_time2SI
      call BuildDensity(atomic,sol)
      if((.not.gen%compElec).and.(gen%electrostatics==k_electrostaticsMultipoles)) then
        call initQvs(atomic,gen,sol,tb,sol%density)
       endif
!             if (.not.gen%comp_elec) then
!                if (gen%electrostatics==tbu_multi) call init_qvs(density)
!             endif
      if (gen%scf) then
        call AddH2(gen,atomic,sol,tb,io)
      endif
      call ZeroMatrix(sol%rhodot,io)
      call Commutator(sol%rhodot,sol%h,sol%rho,io)
      call MatrixCeaApbB(sol%deltaRho,sol%rho,sol%rho0,k_cone,-k_cone,io)
      if (mod(istep,gen%EulerSteps)==0) then !euler step
        call ScalarTMatrix(ihbar*cmplx(dt,0.0_k_pr,k_pr),sol%rhodot,io)
        call ScalarTMatrix(cmplx(gamma*dt,0.0_k_pr,k_pr),sol%deltaRho,io)
        call MatrixCeaApbB(sol%rhonew,sol%rho,sol%rhodot,k_cone,k_cone,io)
        ts=dt
      else !verlet step
        call ScalarTMatrix(ihbar*st,sol%rhodot,io)
        call ScalarTMatrix(gamma*st,sol%deltaRho,io)
        call MatrixCeaApbB(sol%rhonew,sol%rhoold,sol%rhodot,k_cone,k_cone,io)
        ts=2.0_k_pr*dt
      end if
      call ZeroDiagonalMatrix(sol%deltaRho,io)
      call MatrixCeaApbB(sol%rhonew,sol%rhonew,sol%deltaRho,k_cone,k_cone,io)
      ! at this point rho contains the rho at time=t
       ! propagate the positions
       ! calculates positions at t+dt
      do k=1,atomic%atoms%nmoving
        i=atomic%atoms%moving(k)
        mi = atomic%species%mass(atomic%atoms%sp(i))
        atomic%atoms%x(i) = atomic%atoms%x(i) &
         + dt * atomic%atoms%vx(i) &
         + 0.5_k_pr * dt*dt * atomic%atoms%fx(i) / mi
        atomic%atoms%y(i) = atomic%atoms%y(i) &
         + dt * atomic%atoms%vy(i) &
         + 0.5_k_pr * dt*dt * atomic%atoms%fy(i) / mi
        atomic%atoms%z(i) = atomic%atoms%z(i) &
         + dt * atomic%atoms%vz(i) &
         + 0.5_k_pr * dt*dt * atomic%atoms%fz(i) / mi
      enddo
       ! store forces at t in fold
      do k=1,atomic%atoms%nmoving
        i=atomic%atoms%moving(k)
        atomic%atoms%fxo(i) = atomic%atoms%fx(i)
        atomic%atoms%fyo(i) = atomic%atoms%fy(i)
        atomic%atoms%fzo(i) = atomic%atoms%fz(i)
      enddo
       ! shuffle the DMs, rho is now rho(t+dt)
      call CopyMatrix(sol%rhoold,sol%rho,io)
      call CopyMatrix(sol%rho,sol%rhonew,io)
           ! calculate forces at t+dt
      if ((atomic%atoms%nmoving == 0).or.(gen%scf)) then
        call CopyMatrix(sol%h,sol%hin,io)
      else
        call BuildHamiltonian(io,gen,atomic,tb,sol)
      endif
       ! Ramp for the bias
      if ((gen%BiasRampSteps>0).and.((istep)<=gen%BiasRampSteps)) then
        bfa = real(istep,k_pr)/real(gen%BiasRampSteps,k_pr)
        biasFactor = -(bfa-1)**3 * (1 + 3*bfa + 6*bfa**2)
        call AddBias(biasFactor,atomic,sol)
      endif

      call BuildDensity(atomic,sol)
      if((.not.gen%compElec).and.(gen%electrostatics==k_electrostaticsMultipoles)) then
        call initQvs(atomic,gen,sol,tb,sol%density)
      endif
!             if (.not.gen%comp_elec) then
!                if (gen%electrostatics==tbu_multi) call init_qvs(density)
!             endif
      call ZeroForces(atomic)
      call RepulsiveForces(gen,atomic%atoms,tb)
      call electronicForces(atomic,gen,tb,sol,io)
      if (gen%scf) then
        call ScfForces(gen,atomic,sol,tb,io)
      endif
       ! calculate velocities at t+dt
      do k=1,atomic%atoms%nmoving
        i=atomic%atoms%moving(k)
        mi = atomic%species%mass(atomic%atoms%sp(i))
        atomic%atoms%vx(i) = atomic%atoms%vx(i) &
         + 0.5_k_pr * dt * (atomic%atoms%fx(i) + atomic%atoms%fxo(i)) / mi
        atomic%atoms%vy(i) = atomic%atoms%vy(i) &
         + 0.5_k_pr * dt * (atomic%atoms%fy(i) + atomic%atoms%fyo(i)) / mi
        atomic%atoms%vz(i) = atomic%atoms%vz(i) &
         + 0.5_k_pr * dt * (atomic%atoms%fz(i) + atomic%atoms%fzo(i)) / mi
      enddo
       ! scale velocities
      if (gen%scaleVelocities) then
        call ScaleVelocities(gen,atomic)
      endif
      if(mod(istep,gen%AnimationSteps)==0) then
        if (gen%spin) then
          trrho   = MatrixTrace(sol%rho,io)
        else
          trrho   = 2.0_k_pr * MatrixTrace(sol%rho,io)
        endif
        eenergy = ElectronicEnergy(gen,sol,io)
        renergy = RepulsiveEnergy(gen,atomic%atoms,tb)
        if (gen%scf) then
          scfE = ScfEnergy(gen,atomic,sol,tb,io)
        else
          scfE = 0.0_k_pr
        endif
        penergy = eenergy + renergy + scfE
        kenergy = KineticEnergy(atomic)

        if (gen%writeAnimation) then
        call CalcExcessCharges(gen,atomic,sol)
        call CalcDipoles(gen,atomic,sol,tb)
!           write(accUnit,*) gen%CurrSimTime, ChargeOnGroup(atomic%atoms%acceptor,atomic%atoms)
!           write(donUnit,*) gen%CurrSimTime, ChargeOnGroup(atomic%atoms%donor,atomic%atoms)
!           write(spacUnit,*) gen%CurrSimTime, ChargeOnGroup(atomic%atoms%spacer,atomic%atoms)
        write(saux,'(a,f0.8,a)')"Time = ", gen%CurrSimTime," fs"
        call PrintXYZ(io%uani,atomic,.false.,trim(saux))
! decide if is necessary to update neighbours
        if (atomic%atoms%nmoving /=0) then
          call UpdateNeighboursList(atomic,sol,tb,io)
        endif
        if (gen%scf) then
          call AddH2(gen,atomic,sol,tb,io)
        endif
        call Commutator(sol%rhodot,sol%h,sol%rho,io)
        call ScalarTMatrix(ihbar,sol%rhodot,io)

        call ComputeBondCurrents(gen,atomic,sol,io,OrbitalCurrent)
        call PrintBondCurrents(bchUnit,atomic,sol,trim(saux),1.0_k_pr)
        if (OrbitalCurrent) then
          do i=1,atomic%atoms%ncurrentOnBOnds
            call ComputeBondCurrentsOnOrbitals(gen,atomic,sol,io,atomic%atoms%currentOnBonds(2*i-1),atomic%atoms%currentOnBonds(2*i))
            call PrintBondCurrents(currUnit(i),atomic,sol,trim(saux),1.0_k_pr)
          enddo
        endif
      endif
      if ((atomic%atoms%nmoving == 0).or.(gen%scf)) then
        call CopyMatrix(sol%h,sol%hin,io)
      else
        call BuildHamiltonian(io,gen,atomic,tb,sol)
      endif
        write(eneunit,'(7f25.18)')gen%CurrSimTime,renergy,eenergy,scfE,kenergy,penergy+kenergy,real(trrho)
      endif
    enddo !istep loop
    if (gen%writeAnimation) then
      close(xunit)
      close(runit)
      close(accUnit)
      close(donUnit)
      close(spacUnit)
      close(bchUnit)
      if (OrbitalCurrent) then
        do i=1,atomic%atoms%ncurrentOnBOnds
          close(currUnit(i))
        enddo
        deallocate(currUnit)
      endif
    endif
    close(eneunit)
    write(io%uout,'(/a/)')&
      'End Ehrenfest Damped-------------------------------------------------------------'
  end subroutine EhrenfestDynamicsDamped

  subroutine GetRho(rho)
    type(matrixType), intent(inout) :: rho
    integer :: ua, ub, ud,i,j,shift,n,m,ci,cj
    real(k_pr), allocatable :: a(:,:)
    ua=GetUnit()
    ub=GetUnit()
    ud=GetUnit()
    allocate(a(1:rho%dim,1:rho%dim))
    shift=rho%dim/2
    a=0.0_k_pr
    ci=1
    cj=1
    ! read acceptor
    open(unit=ua,file="rhoacceptor.dat",status="old", action="read")
    read(ua,*)n,m
    do i=1,n
      read(ua,*)(a(i,j),j=1,m)
    enddo
    do i=ci,ci+n/2-1
      do j=cj,cj+m/2-1
        rho%a(i,j)=cmplx(a(i,j),0.0_k_pr,k_pr)
        rho%a(i+shift,j+shift)=cmplx(a(i+n/2,j+m/2),0.0_k_pr,k_pr)
      enddo
    enddo
    close(ua)
!      do i=1,n
!       do j=1,m
!          write(777,'(x,f8.4,x)',advance="no") a(i,j)
!        enddo
!        write(777,*)
!      enddo
    ci=ci+n/2
    cj=cj+m/2
    open(unit=ub,file="rhobridge.dat",status="old", action="read")
    a=0.0_k_pr
    read(ub,*)n,m
    do i=1,n
      read(ub,*)(a(i,j),j=1,m)
    enddo
!     do i=1,n
!       do j=1,m
!          write(778,'(x,f8.4,x)',advance="no") a(i,j)
!        enddo
!        write(778,*)
!      enddo
    do i=ci,ci+n/2-1
      do j=cj,cj+m/2-1
        rho%a(i,j)=cmplx(a(i-ci+1,j-cj+1),0.0_k_pr,k_pr)
        rho%a(i+shift,j+shift)=cmplx(a(i-ci+1+n/2,j-cj+1+m/2),0.0_k_pr,k_pr)
      enddo
    enddo
    close(ub)
    ci=ci+n/2
    cj=cj+m/2
    open(unit=ud,file="rhodonor.dat",status="old", action="read")
    a=0.0_k_pr
    read(ud,*)n,m
    do i=1,n
      read(ud,*)(a(i,j),j=1,m)
    enddo
    close(ud)
!     do i=1,n
!       do j=1,m
!         write(779,'(x,f8.4,x)',advance="no") a(i,j)
!       enddo
!       write(779,*)
!     enddo
    do i=ci,ci+n/2-1
      do j=cj,cj+m/2-1
        rho%a(i,j)=cmplx(a(i-ci+1,j-cj+1),0.0_k_pr,k_pr)
        rho%a(i+shift,j+shift)=cmplx(a(i-ci+1+n/2,j-cj+1+m/2),0.0_k_pr,k_pr)
      enddo
    enddo

!      do i=1,rho%dim
!       do j=1,rho%dim
!          write(*,'(x,f8.4,x)',advance="no") real(rho%a(i,j))
!        enddo
!        write(*,*)
!      enddo
    deallocate(a)
  end subroutine GetRho

!> \brief driver routine for geometry optimization
!> \author Alin M Elena
!> \date 30/05/08, 15:22:53
!> \param io type(ioType) contains all the info about I/O files
!> \param gen type(generalType) contains the info needed by the program to k_run
!> \param atomic type(atomicxType) contains all info about the atoms and basis set and some parameters
!> \param tb type(modelType) contains information about the tight binding model parameters
!> \param sol type(solutionType) contains information about the solution space
  subroutine Geometry(io,gen,atomic,tb,sol)
    character(len=*), parameter :: myname = 'driverBFGS'
    type(ioType), intent(inout) :: io
    type(generalType), intent(inout) :: gen
    type(atomicxType), intent(inout) :: atomic
    type(solutionType), intent(inout) :: sol
    type(modelType), intent(inout) :: tb
    select case(gen%geomAlg)
      case(k_lbfgs)
        call linearBFGS(io,gen,atomic,tb,sol,UpdatePoint)
      case(k_bfgs)
        call driverBFGS(io,gen,atomic,tb,sol,UpdatePoint)
    end select
  end subroutine Geometry

integer function UpdatePoint(gen,atomic,tb,sol,io,x,f,gradient)
    character(len=*), parameter :: myname = 'UpdatePoint'
    type(ioType), intent(inout) :: io
    type(generalType), intent(inout) :: gen
    type(atomicxType), intent(inout) :: atomic
    type(solutionType), intent(inout) :: sol
    type(modelType), intent(inout) :: tb
    real(k_pr), intent(inout) :: f
    real(k_pr), intent(inout), optional ::gradient(:)
    real(k_pr), intent(in) :: x(:)
    integer :: i,atom
    character(len=k_mw) :: saux
    UpdatePoint=0
    do i=1,atomic%atoms%nmoving
      atom=atomic%atoms%id(atomic%atoms%moving(i))
      atomic%atoms%x(atom) = x(3*(i-1)+1)
      atomic%atoms%y(atom) = x(3*(i-1)+2)
      atomic%atoms%z(atom) = x(3*(i-1)+3)
    enddo
    call SinglePoint(io,gen,atomic,tb,sol)
    if (.not.gen%lIsSCFConverged) then
      UpdatePoint=1
      gen%scf=.false.
      call error(myname,"change to non-SCF calculation for this point",.false.,io)
      call SinglePoint(io,gen,atomic,tb,sol)
      gen%scf=.true.
    endif
    if (present(gradient)) then
      do i=1,atomic%atoms%nmoving
        atom=atomic%atoms%id(atomic%atoms%moving(i))
        gradient(3*(i-1)+1) =  -atomic%atoms%fx(atom)
        gradient(3*(i-1)+2) =  -atomic%atoms%fy(atom)
        gradient(3*(i-1)+3) =  -atomic%atoms%fz(atom)
      enddo
    endif
    f=sol%totalEnergy
    if (gen%writeAnimation) then
      write(saux,"(a,f16.8)")"E = ",f
      call PrintXYZ(io%uani,atomic,.false.,trim(saux))
    endif
   end function UpdatePoint


end module m_DriverRoutines
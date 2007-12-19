!> \brief controls the fitting process
!> \author Alin M Elena
!> \date 14/11/07, 10:11:09
!> \remarks This module is highly non standard and using it means customizing part of the code.\n
!> There are few routines that need to me modified according to the problem that needs solved.
!> - UpdateParams
!>  sets the parameters to the values contained by the yfit array. yfit array is the only parameter that
!>  should be present other may be added if necessary
!> - SetInitialParams
!>  initializes the parameters to be fit. Everything is set in the array x which is the only parameter
!>  that should be present at all time. Other may appear if necessary
!> - UpdateCost computes the cost for our fit for a set of fit parameters given by the array yfit. The rest of parameters should not be touched for peace of mind
!> - PrintFit prints the fit second part of the routine may be used to print in the desired format the fit (easy to use in the program)

module m_Fit
  use m_Constants
  use m_Types
  use m_Useful
  use m_SA
  use m_Simplex
  use m_SimplexSA
  use m_Useful
  use m_DriverRoutines
  use m_Gutenberg
  use m_TightBinding
  implicit none
  private
  public  :: fitting

  type, public :: fitDataType
  real(k_pr), pointer :: x(:)
  real(k_pr), pointer :: exper(:)
    real(k_pr), pointer :: fit(:)
  integer :: n
  end type fitDataType

  type(fitDataType),public :: fitData
  real(k_pr), public,pointer :: y(:),p(:,:),best(:),bounds(:,:)
  
! private variables
  character(len=100), parameter :: cExper="experiment.dat"
  character(len=100), parameter :: cOutFit="fitout.dat"
  character(len=100), parameter :: cBounds="bounds.dat"
  character(len=100), parameter :: cRestart="restartfit.dat"
  character(len=100), parameter :: cFdfFile="new_ch_param.fdf"
  character(len=100), parameter :: cAtomicData="new_AtomicData.fdf"

contains


  subroutine SetInitialParams(x, atomic,tb)
    character(len=*), parameter :: sMyName="SetInitialParams"
    real(k_pr), intent(inout) :: x(:)
    type(atomicxType), intent(in) :: atomic
    type(modelType), intent(in) :: tb

      x(1) =  tb%hopping(1,2)%a(1,0,0)
!     x(1) =  tb%hopping(1,1)%eps(0)
!     x(2) =  tb%hopping(1,2)%a(0,0,0)
!     x(3) =  tb%hopping(1,2)%a(1,0,0)
!     x(4) =  atomic%species%jlocal(atomic%atoms%sp(2))
!     x(5) =  atomic%species%ulocal(atomic%atoms%sp(2))
!     x(6) =  tb%hopping(1,2)%n
!     x(7) =  tb%hopping(1,2)%nc
!     x(8) =  atomic%species%jlocal(atomic%atoms%sp(1))
!     x(9) =  atomic%species%ulocal(atomic%atoms%sp(1))
!     x(10) =  0.1_k_pr
!     x(11) = 0.1_k_pr
!     x(12) = tb%hopping(1,2)%rc
!     x(13) = tb%hopping(1,1)%a(0,0,0)
!     x(14) = tb%hopping(1,1)%a(0,1,0)
!     x(15) = tb%hopping(1,1)%a(1,1,0)
!     x(16) = tb%hopping(1,1)%a(1,1,1)
!     x(17) = tb%hopping(1,1)%rc
!     x(18) = tb%hopping(1,1)%n
!     x(19) = tb%hopping(1,1)%nc

  end subroutine SetInitialParams

  subroutine UpdateParams(yfit,gen,atomic,tb,sol,io)
    character(len=*), parameter :: myname = 'UpdateParams'
    type(ioType), intent(inout) :: io
    type(generalType), intent(inout) :: gen
    type(atomicxType), intent(inout) :: atomic
    type(solutionType), intent(inout) :: sol
    type(modelType), intent(inout) :: tb
    real(k_pr), intent(in) :: yfit(:)

!     tb%hopping(2,2)%eps(0)=yfit(1)+yfit(10)
!     tb%hopping(2,2)%eps(1)=tb%hopping(2,2)%eps(0)
!     !eso<esn
!     tb%hopping(1,1)%eps(0)=yfit(1)
!     tb%hopping(1,1)%eps(1)=yfit(1)+yfit(11)
! 
!     tb%hopping(1,1)%eps(4)=tb%hopping(1,1)%eps(0)
!     tb%hopping(1,1)%eps(5)=tb%hopping(1,1)%eps(1)
! 
!     tb%hopping(1,2)%a(0,0,0)=yfit(2)
!     tb%hopping(2,1)%a(0,0,0)=yfit(2)
! 
! !     tb%hopping(1,2)%a(0,1,0)=yfit(3)
!     tb%hopping(1,2)%a(1,0,0)=yfit(3)
! 
! !     tb%hopping(2,1)%a(0,1,0)=-yfit(3)
!     tb%hopping(2,1)%a(0,1,0)=-yfit(3)
! 
! 
!     atomic%species%jlocal(atomic%atoms%sp(2))=yfit(4)
!     atomic%species%ulocal(atomic%atoms%sp(2))=yfit(5)
!     tb%hopping(1,2)%n=yfit(6)
!     tb%hopping(1,2)%nc=yfit(7)
!     tb%hopping(2,1)%n=tb%hopping(1,2)%n
!     tb%hopping(2,1)%nc=tb%hopping(1,2)%nc
!     !
!     atomic%species%jlocal(atomic%atoms%sp(1))=yfit(8)
!     atomic%species%ulocal(atomic%atoms%sp(1))=yfit(9)
! 
!     tb%hopping(1,2)%rc = yfit(12)
!     tb%hopping(2,1)%rc = yfit(12)
! 
! 
!     tb%hopping(1,1)%a(0,0,0)=yfit(13)
!     tb%hopping(1,1)%a(0,1,0)=yfit(14)
!     tb%hopping(1,1)%a(1,0,0)=-tb%hopping(1,1)%a(0,1,0)
!     tb%hopping(1,1)%a(1,1,0)=yfit(15)
!     tb%hopping(1,1)%a(1,1,1)=yfit(16)
! 
! 
! 
!     tb%hopping(1,1)%rc = yfit(17)
!     tb%hopping(1,1)%n = yfit(18)
!     tb%hopping(1,1)%nc = yfit(19)
    tb%hopping(1,2)%a(1,0,0)=yfit(1)
    tb%hopping(2,1)%a(0,1,0)=-yfit(1)
    call setTails(io,gen,atomic,tb,sol)
  end subroutine UpdateParams

!> \brief computes the cost function for a set o parameters
!> \author Alin M Elena
!> \date 14/11/07, 09:59:55
!> \param yfit real array the list of parameters for which we compute the cost function
!> \param io type(ioType) contains all the info about I/O files
!> \param gen type(generalType) contains the info needed by the program to k_run
!> \param atomic type(atomicxType) contains all info about the atoms and basis set and some parameters
!> \param tb type(modelType) contains information about the tight binding model parameters
!> \param sol type(solutionType) contains information about the solution space
  function UpdateCost(yfit,gen,atomic,tb,sol,io)
    character(len=*), parameter :: myname = 'UpdateCost'
    real(k_pr),dimension(:), intent(in) :: yfit
    type(ioType), intent(inout) :: io
    type(generalType), intent(inout) :: gen
    type(atomicxType), intent(inout) :: atomic
    type(modelType), intent(inout) :: tb
    type(solutionType), intent(inout) :: sol
    real(k_pr)  :: UpdateCost
    integer :: i,ilevels
    real(k_pr)  :: aux

    call UpdateParams(yfit,gen,atomic,tb,sol,io)
    call SinglePoint(io,gen,atomic,tb,sol)
    if (.not.gen%lIsSCFConverged) then
      UpdateCost=k_infinity
    else
      ilevels=sol%h%dim
      aux=0.0_k_pr
      fitData%fit(1:ilevels)=sol%eigenvals(1:ilevels)

      do i=1,ilevels/2-1
        aux=aux+abs(fitData%exper(i)-fitData%exper(i+1)-(sol%eigenvals(i)-sol%eigenvals(i+1)))
      enddo

      do i=1+ilevels/2, ilevels-1
        aux=aux+abs(fitData%exper(i)-fitData%exper(i+1)-(sol%eigenvals(i)-sol%eigenvals(i+1)))
      enddo
      aux=aux+abs(fitData%exper(1+ilevels/2)-fitData%exper(1)-(sol%eigenvals(1+ilevels/2)-sol%eigenvals(1)))
  ! add charges in the cost function
      do i =1,atomic%atoms%natoms
          fitData%fit(i+ilevels)=atomic%atoms%chrg(i)
          aux=aux+abs(fitData%exper(i+ilevels)-atomic%atoms%chrg(i))
      enddo
      UpdateCost=aux
    endif
end function UpdateCost


!> \brief prints the fit results
!> \author Alin M Elena
!> \date 14/11/07, 12:18:55
!> \param io type(ioType) contains all the info about I/O files
!> \param gen type(generalType) contains the info needed by the program to k_run
!> \param atomic type(atomicxType) contains all info about the atoms and basis set and some parameters
!> \param tb type(modelType) contains information about the tight binding model parameters
!> \param sol type(solutionType) contains information about the solution space
  subroutine PrintFit(gen,atomic,tb,sol,io)
    character(len=*), parameter :: myname="PrintFit"
    type(ioType), intent(inout) :: io
    type(generalType), intent(inout) :: gen
    type(atomicxType), intent(inout) :: atomic
    type(modelType), intent(inout) :: tb
    type(solutionType), intent(inout) :: sol

    integer:: i,j
    real(k_pr) :: aux
    aux=UpdateCost(best,gen,atomic,tb,sol,io)
    open(1,file=trim(cOutFit),status="unknown",action="write")
    do i=1,fitData%n
      write(1,'(i6,4g16.6)')i,fitData%x(i),fitData%exper(i),fitData%fit(i),fitData%exper(i)-fitData%fit(i)
    enddo
    write(1,'(a,f16.8)') "cost:",aux
    close(1)
    open(2,file=trim(cAtomicData),status="unknown",action="write")
    write(2,'(a)') "%block AtomicData"
    do j=1,atomic%species%nspecies
      write(2,'(i0,1x,i0,4f16.8)')j,atomic%species%z(j),atomic%species%mass(j)/k_amuToInternal,atomic%species%ulocal(j),&
        atomic%species%jlocal(j),atomic%species%uinter(j)
    enddo
    write(2,'(a)') "%endblock AtomicData"
    close(2)

  end subroutine PrintFit
! 
!
!> \brief Reads the "experimental" data against which we do the fit
!> \author Alin M Elena
!> \date 14/11/07, 09:58:53
 subroutine InitFit
    character(len=*), parameter :: myname = 'InitFit'
    real(k_pr) :: r1,e1,ri,ei
    integer :: n,err,i
    open(1,file=trim(cExper),status="old",action="read")
    read(1,*)r1,e1
    err=0
    n=0
    do while (err /= -1)
      read(1,*,iostat=err)ri,ei
      n=n+1
    enddo
    close(1)
    fitData%n=n
      allocate(fitData%x(1:n),fitData%exper(1:n),fitData%fit(1:n))
      open(1,file=trim(cExper),status="old",action="read")
    do i=1,n
      read(1,*)fitData%x(i),fitData%exper(i)
    enddo
    close(1)
  end subroutine InitFit
!> \brief reads the bounds of each parameter
!> \author Alin M Elena
!> \date 14/11/07, 10:01:40
!> \param io type(ioType) contains all the info about I/O files
!> \param gen type(generalType) contains the info needed by the program to run
!> \remarks column one keeps the lower limit column two the upper one
  subroutine ReadBounds(gen,io)
      character(len=*), parameter :: myname="ReadBounds"
      type(ioType), intent(inout) :: io
      type(generalType), intent(inout) :: gen
      integer :: i,errno
      character(len=k_ml) :: saux

    allocate(bounds(1:gen%fit%iNoParams,1:2))
    open(1,file=trim(cBounds),status="old",action="read",iostat=errno)
    if (errno/=0) then
      call error("bounds file not found!!!",myname,.true.,io)
    endif  
    do i=1,gen%fit%iNoParams
      read(1,*,iostat=errno)bounds(i,1),bounds(i,2)
      if (errno/=0) then
        write(saux,'(a,i0)')"bounds.dat error in line ",i
        call error(trim(saux),myname,.true.,io)
      endif
    enddo
    close(1)
    call PrintVector(bounds(:,1),'lower bound',.true.,.false.,io)
    call PrintVector(bounds(:,2),'upper bound',.true.,.false.,io)
  end subroutine ReadBounds

!> \brief Driver routine for the fitting process
!> \author Alin M Elena
!> \date 14/11/07, 09:59:55
!> \param io type(ioType) contains all the info about I/O files
!> \param gen type(generalType) contains the info needed by the program to k_run
!> \param atomic type(atomicxType) contains all info about the atoms and basis set and some parameters
!> \param tb type(modelType) contains information about the tight binding model parameters
!> \param sol type(solutionType) contains information about the solution space
  subroutine Fitting(io,gen,atomic,tb,sol)
    character(len=*), parameter :: MyName="Fitting"
    type(ioType), intent(inout) :: io
    type(generalType), intent(inout) :: gen
    type(atomicxType), intent(inout) :: atomic
    type(modelType), intent(inout) :: tb
    type(solutionType), intent(inout) :: sol
    integer :: i,j,kk!,mm
    real(k_pr) ::copt
    real(k_pr),allocatable ::tol(:)
    logical ::quit

    call InitFit
    select case(gen%fit%fitMethod)
      case(k_simplex)
                 ! simplex fit
        call InitSimplex(gen,atomic,tb,sol,io)
          !print on the screen initial p and y
        write(io%uout,*)"---------------------------------------------------"
        write(io%uout,*)"initial values of parameters on first line last value the cost"
        do i=1,gen%fit%iNoParams+1
          write(io%uout, '(11f16.8,f20.8)')(p(i,j),j=1,gen%fit%iNoParams),y(i)
        enddo
        write(io%uout,*)"---------------------------------------------------"
        ! end print
        allocate(best(1:gen%fit%iNoParams),tol(1:gen%fit%neps))
        tol=1e25_k_pr
          call amoeba(p,y,gen%fit%fitTol,UpdateCost,kk,bounds,gen%fit%iter,gen,atomic,tb,sol,io)
        copt=y(1)
        call PrintVector(p(1,:),'current parameters:',.true.,.false.,io)
        do
          call amoeba(p,y,gen%fit%fitTol,UpdateCost,kk,bounds,gen%fit%iter,gen,atomic,tb,sol,io)
          do  i = gen%fit%neps, 2, -1
            tol(i) = tol(i-1)
          enddo
          tol(1)=y(1)
          call PrintVector(p(1,:),'current parameters:',.true.,.false.,io)
          quit = .false.
          if (abs(copt - tol(1)) < gen%fit%fitTol) then
            quit = .true.
          endif

          if(copt>y(1)) then
            best(:)=p(1,:)
            copt=y(1)
          endif
          write(io%uout,*)"current  ",y(1),"and best cost functions",copt
          do  i = 2, gen%fit%neps
            if (abs(tol(1) - tol(i)) > gen%fit%fitTol) then
              quit = .false.
            endif
          enddo
          call PrintVector(best,'best parameters so far:',.true.,.false.,io)
          if (quit) then
            call PrintVector(best,'optimal parameters:',.true.,.false.,io)
            exit
          endif
          p(1,:)=best(:)
          do i=2,gen%fit%iNoParams+1
            do j=1,gen%fit%iNoParams
              if (i-1==j) then
                p(i,j)=bounds(j,1)+abs(bounds(j,2)-bounds(j,1))*ranmar(sol%seed)
              else
                p(i,j)=p(1,j)
              endif
            enddo
          enddo
          do i=1,gen%fit%iNoParams+1
            y(i) = UpdateCost(p(i,:),gen,atomic,tb,sol,io)
          enddo
        enddo
        call UpdateParams(best,gen,atomic,tb,sol,io)
        call PrintFit(gen,atomic,tb,sol,io)
        open(2,file=trim(cRestart),status='unknown',action="write")
        do i=1,gen%fit%iNoParams
          write(2,*) best(i)
        enddo
        close(2)
  !     call print_gsp(trim(cFdfFile))
          ! end simplex fit
        deallocate(y,p,bounds,best,tol)
      case (k_SimplexSA)
        allocate(best(1:gen%fit%iNoParams),tol(1:gen%fit%neps))
        call SimplexSA(gen,atomic,tb,sol,io)
        do i=1,gen%fit%neps
          tol(i)=1e25_k_pr
        enddo
        copt=UpdateCost(best,gen,atomic,tb,sol,io)
        write(io%uout,*)"simplex step"
        do
          p(1,:)=best(:)
          do i=2,gen%fit%iNoParams+1
            do j=1,gen%fit%iNoParams
              if (i-1==j) then
                p(i,j)=bounds(j,1)+abs(bounds(j,2)-bounds(j,1))*ranmar(sol%seed)
              else
                p(i,j)=p(1,j)
              endif
            enddo
          enddo
          do i=1,gen%fit%iNoParams+1
            y(i) = UpdateCost(p(i,:),gen,atomic,tb,sol,io)
          enddo
          call amoeba(p,y,gen%fit%fitTol,UpdateCost,kk,bounds,gen%fit%iter,gen,atomic,tb,sol,io)
          do  i = gen%fit%neps, 2, -1
            tol(i) = tol(i-1)
          enddo
          tol(1)=y(1)
          call PrintVector(p(1,:),'current parameters:',.true.,.false.,io)
          quit = .false.
          if (abs(copt - tol(1)) < gen%fit%fitTol) then
            quit = .true.
          endif
          if(copt>y(1)) then
            best(:)=p(1,:)
            copt=y(1)
          endif
          write(io%uout,*)"current  ",y(1),"and best cost functions",copt
          do  i = 2, gen%fit%neps
            if (abs(tol(1) - tol(i)) > gen%fit%fitTol) then
              quit = .false.
            endif
          enddo
            call PrintVector(best,'best parameters so far:',.true.,.false.,io)
          if (quit) then
            call PrintVector(best,'optimal parameters:',.true.,.false.,io)
            deallocate(tol)
            exit
          endif
        enddo
        call PrintFit(gen,atomic,tb,sol,io)
        open(2,file=trim(cRestart),status='unknown',action="write")
        do i=1,gen%fit%iNoParams
          write(2,*) best(i)
        enddo
        close(2)
  !              call print_gsp(trim(cFdfFile))
        deallocate(y,p,best,bounds)
      case (k_SA)
        allocate(best(1:gen%fit%iNoParams))
        call InitSA(gen,atomic,tb,sol,io)
        call PrintFit(gen,atomic,tb,sol,io)
        deallocate(best)
    end select 

!           ! simulated annealing fit
!     elseif (leqi(gen%fit%fit_type,"sa")) then
!     elseif (leqi(gen%fit%fit_type,"simplexsa")) then

    deallocate(fitData%x,fitData%exper,fitData%fit)

  end subroutine fitting
! 
! 


!> \brief initializes the simplex method
!> \author Alin M Elena
!> \date 14/11/07, 13:35:55
!> \param io type(ioType) contains all the info about I/O files
!> \param gen type(generalType) contains the info needed by the program to k_run
!> \param atomic type(atomicxType) contains all info about the atoms and basis set and some parameters
!> \param tb type(modelType) contains information about the tight binding model parameters
!> \param sol type(solutionType) contains information about the solution space
  subroutine InitSimplex(gen,atomic,tb,sol,io)
    character(len=*), parameter :: myname = 'InitSimplex'
    integer :: i,j,errno
    type(ioType), intent(inout) :: io
    type(generalType), intent(inout) :: gen
    type(atomicxType), intent(inout) :: atomic
    type(solutionType), intent(inout) :: sol
    type(modelType), intent(inout) :: tb

    allocate(y(1:gen%fit%iNoParams+1),p(1:gen%fit%iNoParams+1,gen%fit%iNoParams))
    if (gen%fit%RestartFit) then
      open(2,file=trim(cRestart),status="old",action="read",iostat=errno)
      if (errno/=0) then
        call error("restart file not found!!!",myname,.true.,io)
      endif
      do i=1,gen%fit%iNoParams
        read(2,*)p(1,i)
      enddo
      close(2)
      call UpdateParams(p(1,:),gen,atomic,tb,sol,io)
    else
      call SetInitialParams(p(1,:),atomic,tb)
    endif
    call ReadBounds(gen,io)
    do i = 1, gen%fit%iNoParams
      if ((p(1,i) < bounds(i,1)) .or. (p(1,i) > bounds(i,2))) then
        write(io%uout,'(a,i0,f16.8,1x,f16.8,1x,f16.8)')"check parameter "&
                  ,i,bounds(i,1),p(1,i),bounds(i,2)
        call error("the starting value (x) is outside the bounds execution terminated without any"&
                        "optimization. lb(i) < x(i) <ub(i), i = 1, n.",myname,.true.,io)
      end if
    enddo

    do i=2,gen%fit%iNoParams+1
      do j=1,gen%fit%iNoParams
        if (i-1==j) then
          p(i,j)=bounds(j,1)+abs(bounds(j,2)-bounds(j,1))*ranmar(sol%seed)
           !generate a  new vertex in the box
        else
          p(i,j)=p(1,j)
        endif
      enddo
    enddo

    do i=1,gen%fit%iNoParams+1
      y(i) = UpdateCost(p(i,:),gen,atomic,tb,sol,io)
    enddo
  end subroutine InitSimplex

!> \brief initializes the simulated annealing method
!> \author Alin M Elena
!> \date 14/11/07, 13:35:55
!> \param io type(ioType) contains all the info about I/O files
!> \param gen type(generalType) contains the info needed by the program to k_run
!> \param atomic type(atomicxType) contains all info about the atoms and basis set and some parameters
!> \param tb type(modelType) contains information about the tight binding model parameters
!> \param sol type(solutionType) contains information about the solution space
  subroutine InitSA(gen,atomic,tb,sol,io)
    character(len=*),parameter :: myname="InitSA"
    type(ioType), intent(inout) :: io
    type(generalType), intent(inout) :: gen
    type(atomicxType), intent(inout) :: atomic
    type(solutionType), intent(inout) :: sol
    type(modelType), intent(inout) :: tb
    real(k_pr),allocatable ::  x(:), xopt(:), c(:), &
            vm(:),fstar(:), xp(:)
    real(k_pr) :: t, eps, rt, fopt
    integer,allocatable::  nacp(:)
    integer ::  ns, nt, nfcnev, ier,  &
            maxevl, iprint, nacc, nobds,i,neps,errno
    logical ::  max

    allocate(x(1:gen%fit%iNoParams),xopt(1:gen%fit%iNoParams),c(1:gen%fit%iNoParams),vm(1:gen%fit%iNoParams),&
             xp(1:gen%fit%iNoParams),nacp(1:gen%fit%iNoParams))

      !  set input parameters.
    max = .false.
    neps=gen%fit%neps
    eps = gen%fit%fitTol
    rt = gen%fit%rt
    ns = gen%fit%ns
    nt = gen%fit%nt
    maxevl = gen%fit%feval
    allocate(fstar(1:neps))
    do i = 1, gen%fit%iNoParams
      c(i) = gen%fit%stepAd
    enddo
    call ReadBounds(gen,io)
    if (gen%fit%RestartFit) then
      open(2,file=trim(cRestart),status="old",action="read",iostat=errno)
      if (errno/=0) then
        call error("restart file not found!!",myname,.true.,io)
      endif
      do i=1,gen%fit%iNoParams
        read(2,*)x(i)
      enddo
      close(2)
      call UpdateParams(x,gen,atomic,tb,sol,io)
    else
      call SetInitialParams(x,atomic,tb)
    endif
    t =  gen%fit%temp
    do i = 1, gen%fit%iNoParams
      vm(i) = gen%fit%step
    enddo
    write(io%uout,1000) gen%fit%iNoParams, max, t, rt, eps, ns, &
            nt, neps, maxevl
    1000  format(/,' simulated annealing ',/, &
            /,' number of parameters: ',i3,'   maximazation: ',l5,&
            /,' initial temp: ', g8.2, '   rt: ',g8.2, '   eps: ',g8.2,&
            /,' ns: ',i3, '   nt: ',i2, '   neps: ',i2,&
            /,' maxevl: ',i10)
    call PrintVector(x,'starting values',.true.,.false.,io)
    call PrintVector(vm,'initial step length',.true.,.false.,io)
    call PrintVector(bounds(:,1),'lower bound',.true.,.false.,io)
    call PrintVector(bounds(:,2),'upper bound',.true.,.false.,io)
    call PrintVector(c,'c vector',.true.,.false.,io)
    write(io%uout,'(a)')"/  ****   end of driver routine output   **** /"
    write(io%uout,'(a)')"****  before call to SimulAnnealing.  ****"
    call SimulAnnealing(gen%fit%iNoParams,x,max,rt,eps,ns,nt,&
                        neps,maxevl,bounds(:,1),bounds(:,2),c,&
                            t,vm,xopt,fopt,nacc,nfcnev,nobds,ier,&
                    fstar,xp,nacp,UpdateCost,gen,atomic,sol,tb,io)
    write(io%uout,'(/,''  ****   results after sa   ****   '')')
    call PrintVector(xopt,'solution',.true.,.false.,io)
    call PrintVector(vm,'final step length',.true.,.false.,io)
    write(io%uout,1001) fopt, nfcnev, nacc, nobds, t, ier
    1001  format(/,' optimal function value: ',g20.13 &
            /,' number of function evaluations:     ',i10,&
            /,' number of accepted evaluations:     ',i10,&
            /,' number of out of bound evaluations: ',i10,&
            /,' final temp: ', g20.13,'  ier: ', i3)
    best=xopt
    call UpdateParams(xopt,gen,atomic,tb,sol,io)
    open(2,file=trim(cRestart),status='unknown',action="write")
    do i=1,gen%fit%iNoParams
      write(2,*) x(i)
    enddo
    close(2)
!     call print_gsp(trim(cFdfFile))
  end subroutine InitSA

!> \brief initializes the simplex-simulated annealing method
!> \author Alin M Elena
!> \date 14/11/07, 13:48:55
!> \param io type(ioType) contains all the info about I/O files
!> \param gen type(generalType) contains the info needed by the program to k_run
!> \param atomic type(atomicxType) contains all info about the atoms and basis set and some parameters
!> \param tb type(modelType) contains information about the tight binding model parameters
!> \param sol type(solutionType) contains information about the solution space
  subroutine SimplexSA(gen,atomic,tb,sol,io)
    character(len=*),parameter :: myname="SimplexSA"
    type(ioType), intent(inout) :: io
    type(generalType), intent(inout) :: gen
    type(atomicxType), intent(inout) :: atomic
    type(solutionType), intent(inout) :: sol
    type(modelType), intent(inout) :: tb
    real(k_pr) :: opt(1:gen%fit%iNoParams),yb,temperature,copt
    integer  :: i,iter
    logical :: quit
    real(k_pr), allocatable :: tol(:)
        !init simplex
    call InitSimplex(gen,atomic,tb,sol,io)
    yb=huge(yb)
    allocate(tol(1:gen%fit%neps))
    do i=1,gen%fit%neps
      tol(i)=1e20_k_pr
    enddo
        !end init simplex
    temperature=gen%fit%temp
    write(io%uout,*)"simulated annealing stage"
    write(io%uout,*)"initial values:"
    call PrintVector(p(1,:),"initial parameters",.true.,.false.,io)
    write(io%uout,*)"starting temperature: ",gen%fit%temp
    write(io%uout,*)"maximum simplex iterations: ",gen%fit%iter
    write(io%uout,*)"fit tolerance: ",gen%fit%fitTol
    write(io%uout,*)" temperature reduction factor: ",gen%fit%rt
    copt=UpdateCost(p(1,:),gen,atomic,tb,sol,io)
    write(io%uout,*)"initial cost function: ",copt
    best(:)=p(1,:)
    do
      iter=gen%fit%iter/10
      call amebsa(p,y,opt,yb,gen%fit%fitTol,UpdateCost,iter,temperature,bounds,gen,atomic,tb,sol,io)
      do  i = gen%fit%neps, 2, -1
        tol(i) = tol(i-1)
      enddo
      tol(1)=yb
      write(io%uout,*)"current temperature: ",temperature
      call PrintVector(opt,'current parameters:',.true.,.false.,io)
      quit = .false.
      if (abs(copt - tol(1)) < gen%fit%fitTol) then
        quit = .true.
      endif
      if(copt>yb) then
        best(:)=opt(:)
        copt=yb
      endif
      write(io%uout,*)"current  ",yb,"and best cost functions",copt
      do  i = 2, gen%fit%neps
        if (abs(tol(1) - tol(i)) > gen%fit%fitTol) then
          quit = .false.
        endif
      enddo
      call PrintVector(best,'best parameters so far:',.true.,.false.,io)
      if (quit) then
        call PrintVector(opt,'optimal parameters:',.true.,.false.,io)
        deallocate(tol)
        return
      endif
      temperature=temperature*gen%fit%rt
      if(temperature<epsilon(temperature)) then
        write(io%uout,*)"temperature under machine precision!!!"
        deallocate(tol)
        return
      endif
    enddo
  end subroutine SimplexSA
end module m_Fit